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
end
