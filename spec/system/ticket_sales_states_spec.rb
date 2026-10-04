require "rails_helper"

RSpec.describe "Closed ticket sales", type: :system do
  [ 1280, 390 ].each do |width|
    it "keeps closed tiers unavailable and Late Bird purchasable at #{width}px" do
      early = create(:ticket_type, name: "Early Bird", slug: "conference-pass-early-bird", active: false, capacity: 30, position: 1)
      regular = create(:ticket_type, name: "Regular", slug: "conference-pass-regular", active: false, capacity: 140, position: 2)
      late = create(:ticket_type, name: "Late Bird", slug: "conference-pass-late-bird", price_paise: 450_000, capacity: 30, position: 3)
      create_list(:ticket, 29, ticket_type: early, order: create(:order, :paid))
      create_list(:ticket, 86, ticket_type: regular, order: create(:order, :paid))
      page.current_window.resize_to(width, 900)

      visit tickets_store_path

      expect(page).to have_css("h1", text: "Choose your pass")
      page.save_screenshot("ticket-sales-#{width}.png", full: true)
      [ early, regular ].each do |type|
        within find(".ticket-card", text: type.name) do
          expect(page).to have_css(".ticket-state-badge", text: "SALES CLOSED")
          expect(page).to have_css(".ticket-unavailable", text: "Sales for this tier have closed.")
          expect(page).to have_no_css(".quantity-stepper")
          expect(page).to have_no_field("checkout_quantities_#{type.id}")
        end
      end
      within find(".ticket-card", text: regular.name) do
        expect(page).to have_css(".ticket-availability", text: "54 of 140 left")
      end
      within find(".ticket-card", text: late.name) do
        expect(page).to have_css(".ticket-state-badge", text: "ON SALE")
        expect(page).to have_css(".ticket-price-amount", text: "₹4,500")
        expect(page).to have_css(".ticket-price-note", text: "GST included")
        find("[aria-label='Add one #{late.name}']").click
        expect(page).to have_field("checkout_quantities_#{late.id}", with: "1")
      end
      expect(page).to have_no_content("This tier has sold out.")
      expect(Order.count).to eq(2)
      expect(Ticket.count).to eq(115)
    end
  end
end
