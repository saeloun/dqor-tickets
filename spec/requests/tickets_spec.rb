require "rails_helper"

RSpec.describe "Tickets", type: :request do
  it "shows visible ticket types with their sale states and add-on gate" do
    on_sale = create(:ticket_type, name: "Early Bird", slug: "conference-pass-early-bird", price_paise: 350_000, capacity: 30, max_per_order: 25, position: 1)
    sold_out = create(:ticket_type, name: "Sold Out", capacity: 1, position: 2)
    coming_soon = create(:ticket_type, name: "Late Bird", active: false, position: 3)
    create(:ticket_type, name: "Explore Pune Day", slug: "explore-pune-day", active: false, requires_conference_pass: true, position: 4)
    unlimited = create(:ticket_type, name: "Community Pass", slug: "conference-pass-community", capacity: nil, max_per_order: 3, position: 5)
    rails_girls = create(:ticket_type, name: "Rails Girls Pune Pass", slug: "rails-girls-pune", description: "One-day beginner workshop", price_paise: 35_000, position: 6)
    create(:ticket_type, name: "Hidden", hidden: true)
    create_list(:ticket, 7, ticket_type: on_sale, order: create(:order, :paid))
    create(:ticket, ticket_type: sold_out, order: create(:order, :paid))

    get tickets_store_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(on_sale.name, "on sale", "₹3,500", "23 of 30 left", %(max="23"))
    expect(response.body).to include(sold_out.name, "sold out")
    expect(response.body).to include(coming_soon.name, "coming soon")
    expect(response.body).to include(%(class="ticket-availability ticket-availability--low">0 of 1 left))
    expect(response.body).to include("Add Explore Pune Day", "Paid order code", "Coupon code")
    expect(response.body).to include(rails_girls.name, "₹350", "October 10, 2026 (Saturday)", "Build a Rails app with coaches")
    expect(response.parsed_body.at_css("input[data-ticket-type-id='#{rails_girls.id}']")['data-ticket-kind']).to eq("standalone")
    expect(response.body).not_to include("Hidden")

    unlimited_card = response.parsed_body.css(".ticket-card").find { |card| card.text.include?(unlimited.name) }
    expect(unlimited_card.at_css(".ticket-availability")).to be_nil
    expect(unlimited_card.at_css("input[type=number]")["max"]).to eq("3")
  end

  describe "ticket choices" do
    let!(:early_bird) { create(:ticket_type, name: "Early Bird", slug: "conference-pass-early-bird", capacity: 0, position: 1) }
    let!(:regular) { create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", position: 2) }
    let!(:late_bird) { create(:ticket_type, name: "Late Bird", slug: "conference-pass-late-bird", active: false, position: 3) }
    let!(:supporter) { create(:ticket_type, name: "Supporter Pass", slug: "supporter-pass", position: 4) }
    let!(:rails_girls) { create(:ticket_type, name: "Rails Girls Pune", slug: "rails-girls-pune", price_paise: 35_000, position: 5) }
    let!(:add_on) { create(:ticket_type, name: "Explore Pune Day", slug: "explore-pune-day", requires_conference_pass: true, position: 6) }

    it "puts an available conference pass and Rails Girls first, with one card and control per type" do
      get tickets_store_path

      document = response.parsed_body
      expect(document.css(".tickets-grid--primary .ticket-card").map { |card| card["id"] }).to eq([ regular, rails_girls ].map { |type| "ticket_type_#{type.id}" })
      expect(document.css(".ticket-card-title").map(&:text)).to eq([ regular, rails_girls, early_bird, late_bird, supporter, add_on ].map(&:name))
      expect(document.css("form.checkout-form").size).to eq(1)
      [ regular, rails_girls, supporter, add_on ].each do |type|
        expect(document.css("input[name='checkout[quantities][#{type.id}]']").size).to eq(1)
      end
      expect(document.at_css(".ticket-choices a[href='#ticket_type_#{regular.id}']").text).to eq("DQOR tickets")
      expect(document.at_css(".ticket-choices a[href='#ticket_type_#{rails_girls.id}']").text).to eq("Rails Girls tickets")
    end

    it "keeps sold-out and upcoming Rails Girls visible without enabling purchase" do
      [ { capacity: 0 }, { capacity: 10, active: false } ].each do |attributes|
        rails_girls.update!(attributes)
        get tickets_store_path

        card = response.parsed_body.at_css(".tickets-grid--primary #ticket_type_#{rails_girls.id}")
        expect(card).to be_present
        expect(card.at_css("input")).to be_nil
        expect(card.at_css(".ticket-unavailable")).to be_present
      end
    end

    it "uses the next available conference tier when the earlier tiers cannot be purchased" do
      regular.update!(sales_end_at: 1.day.ago)
      late_bird.update!(active: true, capacity: nil)

      get tickets_store_path

      expect(response.parsed_body.css(".tickets-grid--primary .ticket-card").map { |card| card["id"] }).to eq([ late_bird, rails_girls ].map { |type| "ticket_type_#{type.id}" })
    end

    it "falls back to the first visible conference tier when none are available" do
      regular.update!(active: false)
      early_bird.update!(hidden: true)

      get tickets_store_path

      expect(response.parsed_body.css(".tickets-grid--primary .ticket-card").map { |card| card["id"] }).to eq([ regular, rails_girls ].map { |type| "ticket_type_#{type.id}" })
      expect(response.parsed_body.at_css("#ticket_type_#{early_bird.id}")).to be_nil
    end

    it "omits the Rails Girls shortcut and card when that choice is hidden or absent" do
      rails_girls.update!(hidden: true)
      get tickets_store_path

      expect(response.parsed_body.at_css(".ticket-choices").text).to include("DQOR tickets")
      expect(response.parsed_body.css(".ticket-choices a").map(&:text)).to eq([ "DQOR tickets" ])
      expect(response.parsed_body.at_css("#ticket_type_#{rails_girls.id}")).to be_nil

      rails_girls.destroy!
      get tickets_store_path
      expect(response.parsed_body.css(".ticket-choices a").map(&:text)).to eq([ "DQOR tickets" ])
    end

    it "offers Rails Girls on its own when all conference tiers are hidden" do
      [ early_bird, regular, late_bird ].each { |type| type.update!(hidden: true) }
      get tickets_store_path

      expect(response.body).not_to include("DQOR tickets")
      expect(response.parsed_body.css(".tickets-grid--primary .ticket-card").map { |card| card["id"] }).to eq([ "ticket_type_#{rails_girls.id}" ])
    end

    it "retains both choices when checkout re-renders an invalid selection" do
      post orders_path, params: { checkout: { buyer_name: "Ada", email: "ada@example.com", quantities: { regular.id.to_s => "0" } } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.at_css(".alert").text).to include("select at least one ticket")
      expect(response.parsed_body.css(".tickets-grid--primary .ticket-card").map { |card| card["id"] }).to eq([ regular, rails_girls ].map { |type| "ticket_type_#{type.id}" })
      expect(response.parsed_body.css(".ticket-choices a").map(&:text)).to eq([ "DQOR tickets", "Rails Girls tickets" ])
    end
  end
end
