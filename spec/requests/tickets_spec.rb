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
end
