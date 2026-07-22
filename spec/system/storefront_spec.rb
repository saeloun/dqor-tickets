require "rails_helper"

RSpec.describe "Storefront", type: :system do
  it "lists ticket types with prices and availability" do
    create(:ticket_type, name: "Early Bird", slug: "conference-pass-early-bird", price_paise: 350_000, capacity: 30, position: 1)

    visit root_path

    expect(page).to have_content("Early Bird")
    expect(page).to have_content("₹3,500")
  end
end
