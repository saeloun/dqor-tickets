require "rails_helper"

RSpec.describe "Home", type: :request do
  it "renders the conference home with a tickets call to action" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Deccan Queen on Rails")
    expect(response.body).to include("Get your pass")
    expect(response.body).to include(tickets_store_path)
  end

  it "links the branded favicons, not the generic Rails placeholder" do
    get root_path

    expect(response.body).to include('href="/favicon.ico"')
    expect(response.body).to include('href="/dqor/favicon-32x32.png"')
    expect(response.body).to include('sizes="180x180" href="/dqor/apple-touch-icon.png"')
    expect(response.body).not_to include("/icon.svg")
  end

  it "serves the ticket storefront at /tickets" do
    get tickets_store_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Choose your pass")
  end

  it "keeps the conference price separate from the Rails Girls price" do
    create(:ticket_type, slug: "conference-pass-regular", price_paise: 350_000)
    create(:ticket_type, slug: "rails-girls-pune", price_paise: 35_000)

    get root_path

    expect(response.body).to include("From ₹3,500")
    expect(response.body).to include("Buy a ticket · ₹350")
  end
  describe "ticket availability" do
    let!(:early) { create(:ticket_type, slug: "conference-pass-early-bird", active: false, price_paise: 350_000) }
    let!(:regular) { create(:ticket_type, slug: "conference-pass-regular", active: false, price_paise: 350_000) }
    let!(:late) { create(:ticket_type, slug: "conference-pass-late-bird", price_paise: 450_000, capacity: 30) }
    let!(:girls) { create(:ticket_type, slug: "rails-girls-pune", price_paise: 35_000) }
    let!(:explore) { create(:ticket_type, slug: "explore-pune-day", price_paise: 200_000, active: false, requires_conference_pass: true) }

    def home_card(kind)
      response.parsed_body.at_css("#tickets .ticket-card--#{kind}")
    end

    it "advertises the available Late Bird price and closes the dormant Explore purchase path" do
      create(:ticket, ticket_type: late, order: create(:order, :paid))
      create(:coupon, ticket_type: nil, uses_count: 2)
      models = [ TicketType, Coupon, Order, Ticket ]
      before = models.to_h { |model| [ model.name, model.order(:id).map(&:attributes) ] }
      get root_path

      expect(home_card("conference").text).to include("From ₹4,500", "Conference afterparty (Oct 8)")
      expect(home_card("conference").at_css("a").text).to eq("Buy Conference Pass")
      expect(home_card("retreat").text).to include("coming soon")
      expect(home_card("retreat").text).not_to include("₹2,000")
      expect(home_card("retreat").at_css("a[href='/tickets']")).to be_nil
      expect(models.to_h { |model| [ model.name, model.order(:id).map(&:attributes) ] }).to eq(before)
    end

    it "does not invent an Explore price or purchase action when the category is absent" do
      explore.destroy!
      get root_path

      expect(home_card("retreat").text).not_to include("₹2,000")
      expect(home_card("retreat").at_css("a[href='/tickets']")).to be_nil
    end

    it "uses configured Explore pricing only while inventory and the sales window permit purchase" do
      explore.update!(active: true, price_paise: 275_000, capacity: 1)
      get root_path
      expect(home_card("retreat").text).to include("₹2,750")
      expect(home_card("retreat").at_css("a[href='/tickets']").text).to eq("Add to Conference Pass")

      create(:ticket, ticket_type: explore, order: create(:order, :paid))
      get root_path
      expect(home_card("retreat").text).to include("sold out")
      expect(home_card("retreat").at_css("a[href='/tickets']")).to be_nil
    end

    it "excludes hidden and exhausted conference tiers from the advertised minimum price" do
      early.update!(active: true, hidden: true, price_paise: 100_000)
      regular.update!(active: true, capacity: 1, price_paise: 200_000)
      create(:ticket, ticket_type: regular, order: create(:order, :paid))
      get root_path
      expect(home_card("conference").text).to include("From ₹4,500")
      expect(home_card("conference").text).not_to include("₹1,000", "₹2,000")

      late.update!(capacity: 0)
      get root_path
      expect(home_card("conference").text).to include("sold out")
      expect(home_card("conference").text).not_to include("From")
      expect(home_card("conference").at_css("a")).to be_nil
    end

    it "does not advertise hidden Rails Girls or Explore categories for purchase" do
      girls.update!(hidden: true)
      explore.update!(active: true, hidden: true)
      get root_path

      expect(home_card("rails-girls").at_css("a")).to be_nil
      expect(home_card("rails-girls").text).not_to include("₹350")
      expect(response.parsed_body.at_css("#rails-girls a[href='/tickets']")).to be_nil
      expect(home_card("retreat").at_css("a[href='/tickets']")).to be_nil
      expect(home_card("retreat").text).not_to include("₹2,000")
    end

    it "respects pending inventory holds and releases expired holds without changing orders" do
      early.update!(active: true, capacity: 1)
      order = create(:order, expires_at: 30.minutes.from_now)
      create(:ticket, ticket_type: early, order: order)
      before = order.attributes
      get root_path
      expect(home_card("conference").text).to include("From ₹4,500")
      expect(order.reload.attributes).to eq(before)

      order.update!(expires_at: 1.second.ago)
      get root_path
      expect(home_card("conference").text).to include("From ₹3,500")
      expect(order.reload).to be_pending
    end

    it "does not expose hidden or other-event inventory as a conference sale" do
      [ early, regular, late, girls, explore ].each { |type| type.update!(hidden: true) }
      organization = Organization.create!(name: "Other organizer", slug: "other-organizer")
      event = Event.create!(organization: organization, title: "Other event", slug: "other-event", timezone: "Asia/Kolkata")
      create(:ticket_type, slug: "conference-pass-other-event", price_paise: 0, active: false, hidden: true, event_id: event.id)
      get root_path

      expect(home_card("conference").text).to include("unavailable")
      expect(home_card("conference").text).not_to include("From", "₹1,000", "₹3,500", "₹4,500")
      expect(home_card("conference").at_css("a")).to be_nil
    end

    it "does not advertise an empty upcoming tier before an exhausted current tier" do
      travel_to(Time.zone.local(2026, 10, 5, 12)) do
        regular.update!(active: true, capacity: 1, position: 2)
        create(:ticket, ticket_type: regular, order: create(:order, :paid))
        late.update!(capacity: 0, position: 3, sales_start_at: 1.hour.from_now)
        models = [ TicketType, Coupon, Order, Ticket ]
        before = models.to_h { |model| [ model.name, model.order(:id).map(&:attributes) ] }

        get root_path
        expect(home_card("conference").text).to include("sold out")
        expect(home_card("conference").text).not_to include("coming soon", "From")
        expect(home_card("conference").at_css("a")).to be_nil
        expect(models.to_h { |model| [ model.name, model.order(:id).map(&:attributes) ] }).to eq(before)

        late.update!(capacity: 1)
        get root_path
        expect(home_card("conference").text).to include("coming soon")
        expect(home_card("conference").at_css("a")).to be_nil

        create(:ticket, ticket_type: late, order: create(:order, :paid))
        get root_path
        expect(home_card("conference").text).to include("sold out")
        expect(home_card("conference").at_css("a")).to be_nil

        late.update!(capacity: nil)
        get root_path
        expect(home_card("conference").text).to include("coming soon")
        expect(home_card("conference").at_css("a")).to be_nil
      end
    end

    it "keeps the conference coming soon when an earlier tier is exhausted and a later tier has not opened" do
      travel_to(Time.zone.local(2026, 10, 5, 12)) do
        regular.update!(active: true, capacity: 1, position: 2)
        create(:ticket, ticket_type: regular, order: create(:order, :paid))
        late.update!(position: 3, sales_start_at: 1.hour.from_now)
        models = [ TicketType, Coupon, Order, Ticket ]
        before = models.to_h { |model| [ model.name, model.order(:id).map(&:attributes) ] }

        get root_path
        expect(home_card("conference").text).to include("coming soon")
        expect(home_card("conference").text).not_to include("sold out", "From")
        expect(home_card("conference").at_css("a")).to be_nil
        expect(models.to_h { |model| [ model.name, model.order(:id).map(&:attributes) ] }).to eq(before)

        late.update!(hidden: true)
        get root_path
        expect(home_card("conference").text).to include("sold out")
        expect(home_card("conference").at_css("a")).to be_nil

        late.update!(hidden: false)
        travel_to(late.sales_start_at)
        get root_path
        expect(home_card("conference").text).to include("From ₹4,500")
        expect(home_card("conference").at_css("a").text).to eq("Buy Conference Pass")

        late.update!(capacity: 0)
        get root_path
        expect(home_card("conference").text).to include("sold out")
        expect(home_card("conference").at_css("a")).to be_nil
      end
    end

    it "shows future and ended sales without a purchase link and opens at inclusive boundaries" do
      travel_to(Time.zone.local(2026, 10, 5, 12)) do
        late.update!(sales_start_at: 1.hour.from_now)
        get root_path
        expect(home_card("conference").text).to include("coming soon")
        expect(home_card("conference").at_css("a")).to be_nil

        late.update!(sales_start_at: Time.current, sales_end_at: Time.current)
        get root_path
        expect(home_card("conference").text).to include("From ₹4,500")
        expect(home_card("conference").at_css("a")).to be_present

        travel 1.second
        get root_path
        expect(home_card("conference").text).to include("sales closed")
        expect(home_card("conference").at_css("a")).to be_nil
      end
    end
  end

  describe "conference sale precedence" do
    tiers = {
      live: { slug: "conference-pass-regular", price_paise: 350_000, capacity: 1 },
      live_late: { slug: "conference-pass-late-bird", price_paise: 450_000, capacity: 1 },
      exhausted: { slug: "conference-pass-regular", price_paise: 350_000, capacity: 0 },
      exhausted_early: { slug: "conference-pass-early-bird", price_paise: 350_000, capacity: 0 },
      negative: { slug: "conference-pass-regular", price_paise: 350_000, capacity: 0, reserved: 1 },
      future: { slug: "conference-pass-late-bird", price_paise: 450_000, capacity: 1, starts_in: 3600 },
      empty_future: { slug: "conference-pass-late-bird", price_paise: 450_000, capacity: 0, starts_in: 3600 },
      unlimited_future: { slug: "conference-pass-late-bird", price_paise: 450_000, capacity: nil, starts_in: 3600 },
      inactive_future: { slug: "conference-pass-late-bird", price_paise: 450_000, capacity: 1, starts_in: 3600, active: false },
      closed: { slug: "conference-pass-regular", price_paise: 350_000, capacity: 1, active: false },
      closed_early: { slug: "conference-pass-early-bird", price_paise: 350_000, capacity: 1, active: false },
      dormant: { slug: "conference-pass-late-bird", price_paise: 450_000, capacity: 1, active: false },
      ended: { slug: "conference-pass-regular", price_paise: 350_000, capacity: 1, ends_in: -1 },
      boundary: { slug: "conference-pass-late-bird", price_paise: 450_000, capacity: 1, starts_in: 0, ends_in: 0 },
      hidden_live: { slug: "conference-pass-early-bird", price_paise: 100_000, capacity: 1, hidden: true },
      hidden_future: { slug: "conference-pass-late-bird", price_paise: 450_000, capacity: 1, starts_in: 3600, hidden: true },
      free: { slug: "conference-pass-regular", price_paise: 0, capacity: 1 },
      other: { slug: "rails-girls-pune", price_paise: 35_000, capacity: 1 },
      tenant: { slug: "conference-pass-other-event", price_paise: 0, capacity: 1, active: false, hidden: true, tenant: true }
    }
    cases = [
      [ "no tiers", [], "unavailable", nil ],
      [ "hidden tiers only", [ :hidden_live, :hidden_future ], "unavailable", nil ],
      [ "another ticket category only", [ :other ], "unavailable", nil ],
      [ "nonpositive conference price only", [ :free ], "unavailable", nil ],
      [ "staged tenant only", [ :tenant ], "unavailable", nil ],
      [ "inactive Regular", [ :closed ], "sales closed", nil ],
      [ "inactive Early Bird", [ :closed_early ], "sales closed", nil ],
      [ "inactive dormant Late Bird", [ :dormant ], "coming soon", nil ],
      [ "ended sale", [ :ended ], "sales closed", nil ],
      [ "available current tier", [ :live ], "on sale", "From ₹3,500" ],
      [ "cheapest available current tier regardless of position", [ :live_late, :live ], "on sale", "From ₹3,500" ],
      [ "available current before upcoming", [ :live, :future ], "on sale", "From ₹3,500" ],
      [ "available current after upcoming and exhausted", [ :future, :exhausted_early, :live ], "on sale", "From ₹3,500" ],
      [ "available current with empty future", [ :empty_future, :live ], "on sale", "From ₹3,500" ],
      [ "hidden cheaper current excluded", [ :hidden_live, :live_late ], "on sale", "From ₹4,500" ],
      [ "exhausted current only", [ :exhausted ], "sold out", nil ],
      [ "stocked future only", [ :future ], "coming soon", nil ],
      [ "closed first before exhausted current", [ :closed_early, :exhausted ], "sold out", nil ],
      [ "exhausted current before closed", [ :exhausted_early, :closed ], "sold out", nil ],
      [ "exhausted current with stocked future", [ :exhausted, :future ], "coming soon", nil ],
      [ "stocked future before exhausted current", [ :future, :exhausted ], "coming soon", nil ],
      [ "exhausted current with empty future", [ :exhausted, :empty_future ], "sold out", nil ],
      [ "empty future before exhausted current", [ :empty_future, :exhausted ], "sold out", nil ],
      [ "exhausted current with hidden future", [ :exhausted, :hidden_future ], "sold out", nil ],
      [ "negative current inventory with empty future", [ :negative, :empty_future ], "sold out", nil ],
      [ "closed current with stocked future", [ :closed, :future ], "coming soon", nil ],
      [ "stocked future before closed current", [ :future, :closed ], "coming soon", nil ],
      [ "closed first with empty future", [ :closed, :empty_future ], "sales closed", nil ],
      [ "empty future first with closed current", [ :empty_future, :closed ], "coming soon", nil ],
      [ "empty future only retains its tier state", [ :empty_future ], "coming soon", nil ],
      [ "inactive stocked future retains its tier state", [ :exhausted, :inactive_future ], "coming soon", nil ],
      [ "unlimited stocked future", [ :exhausted, :unlimited_future ], "coming soon", nil ],
      [ "inclusive start and end", [ :boundary ], "on sale", "From ₹4,500" ],
      [ "tenant and hidden prices excluded from current sale", [ :tenant, :hidden_live, :live_late ], "on sale", "From ₹4,500" ]
    ]

    cases.each do |description, configuration, state, price|
      it "reports #{state} for #{description}" do
        travel_to(Time.zone.local(2026, 10, 5, 12)) do
          configuration.each_with_index do |kind, position|
            facts = tiers.fetch(kind)
            attributes = facts.except(:starts_in, :ends_in, :reserved, :tenant).merge(position: position)
            attributes[:sales_start_at] = Time.current + facts[:starts_in] if facts.key?(:starts_in)
            attributes[:sales_end_at] = Time.current + facts[:ends_in] if facts.key?(:ends_in)
            if facts[:tenant]
              organization = Organization.create!(name: "Matrix organizer", slug: "matrix-organizer")
              event = Event.create!(organization: organization, title: "Matrix event", slug: "matrix-event", timezone: "Asia/Kolkata")
              attributes[:event_id] = event.id
            end
            ticket_type = create(:ticket_type, **attributes)
            facts.fetch(:reserved, 0).times { create(:ticket, ticket_type: ticket_type, order: create(:order, :paid)) }
          end
          models = [ TicketType, Coupon, Order, Ticket ]
          before = models.to_h { |model| [ model.name, model.order(:id).map(&:attributes) ] }
          get root_path

          expect(response).to have_http_status(:ok)
          card = response.parsed_body.at_css("#tickets .ticket-card--conference")
          if price
            expect(card.text).to include(price)
            expect(card.at_css("a").text).to eq("Buy Conference Pass")
          else
            expect(card.at_css(".ticket-price-amount").text).to eq(state)
            expect(card.text).not_to include("From", "₹")
            expect(card.at_css("a")).to be_nil
          end
          expect(models.to_h { |model| [ model.name, model.order(:id).map(&:attributes) ] }).to eq(before)
        end
      end
    end
  end
end
