require "rails_helper"

RSpec.describe "Conference capacity", type: :system do
  it "shows the conference-only count and closes conference sales while Rails Girls remain available" do
    regular = create(:ticket_type, slug: "conference-pass-regular", capacity: nil)
    girls = create(:ticket_type, slug: "rails-girls-pune", price_paise: 35_000, capacity: nil)
    comp = create(:ticket_type, slug: "complimentary-pass", hidden: true, price_paise: 0, capacity: nil)
    paid = create(:order, :paid)
    199.times { create(:ticket, order: paid, ticket_type: regular) }
    girls_order = create(:order, :paid)
    3.times { create(:ticket, order: girls_order, ticket_type: girls) }
    User.create!(email: "girls-face@example.test", name: "Private workshop face", public_attendee: true)
    girls_order.tickets.first.update!(attendee_email: "girls-face@example.test")
    visit root_path
    expect(page).to have_css(".whos-coming__count strong", text: "199", exact_text: true)
    expect(page).to have_no_css(".whos-coming__face")
    within("#tickets .ticket-card--conference") { expect(page).to have_link("Buy Conference Pass") }
    Order.issue_comps!(emails: "final-comp@example.test")
    page.refresh
    expect(page).to have_css(".whos-coming__count strong", text: "200", exact_text: true)
    within("#tickets .ticket-card--conference") do
      expect(page).to have_content("Sold Out")
      expect(page).to have_no_link("Buy Conference Pass")
    end
    click_link "Buy a ticket · ₹350"
    expect(page).to have_field("checkout_quantities_#{girls.id}", with: "0")
    find("[aria-label='Add one #{girls.name}']").click
    expect(page).to have_css("[data-cart-target='total']", text: "₹350")
    expect(page).to have_no_field("checkout_quantities_#{regular.id}", visible: true)
  end
end
