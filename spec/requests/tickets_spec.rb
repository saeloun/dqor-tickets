require "rails_helper"

RSpec.describe "Tickets", type: :request do
  it "shows visible ticket types with their sale states and add-on gate" do
    on_sale = create(:ticket_type, name: "Regular", slug: "conference-pass-regular", price_paise: 400_000, position: 1)
    sold_out = create(:ticket_type, name: "Sold Out", capacity: 1, position: 2)
    coming_soon = create(:ticket_type, name: "Late Bird", sales_start_at: 1.day.from_now, position: 3)
    create(:ticket_type, name: "Explore Pune Day", slug: "explore-pune-day", requires_conference_pass: true, position: 4)
    create(:ticket_type, name: "Hidden", hidden: true)
    create(:ticket, ticket_type: sold_out, order: create(:order, :paid))

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(on_sale.name, "on sale", "₹4,000")
    expect(response.body).to include(sold_out.name, "sold out")
    expect(response.body).to include(coming_soon.name, "coming soon")
    expect(response.body).to include("Add Explore Pune Day", "Paid order code", "Coupon code", "T-shirt size", "Dietary preference")
    expect(response.body).not_to include("Hidden")
  end
end
