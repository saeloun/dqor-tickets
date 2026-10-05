require "rails_helper"

RSpec.describe "Home ticket availability", type: :system do
  let!(:early) { create(:ticket_type, name: "Early Bird", slug: "conference-pass-early-bird", active: false, price_paise: 350_000, position: 1) }
  let!(:regular) { create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", active: false, price_paise: 350_000, position: 2) }
  let!(:late) { create(:ticket_type, name: "Late Bird", slug: "conference-pass-late-bird", price_paise: 450_000, position: 3) }
  let!(:girls) { create(:ticket_type, name: "Rails Girls Pune", slug: "rails-girls-pune", price_paise: 35_000, position: 5) }
  let!(:explore) { create(:ticket_type, name: "Explore Pune Day", slug: "explore-pune-day", price_paise: 200_000, active: false, requires_conference_pass: true) }

  [ [ "desktop", 1400, 1200 ], [ "mobile", 390, 844 ] ].each do |layout, width, height|
    it "shows available choices without a dormant add-on purchase path on #{layout}" do
      page.current_window.resize_to(width, height)
      visit root_path
      within("#tickets") do
        expect(page).to have_css(".ticket-card--conference .ticket-price", text: "From ₹4,500")
        find(".ticket-card--retreat").scroll_to(:center)
        page.save_screenshot("home-ticket-availability-#{layout}.png")
        within(".ticket-card--retreat") do
          expect(page).to have_content("Coming Soon")
          expect(page).to have_no_content("₹2,000")
          expect(page).to have_no_link("Add to Conference Pass")
          expect(page).to have_link("See what's planned →")
        end
        click_link "Buy Conference Pass"
      end

      expect(page).to have_css(".tickets-grid--primary .ticket-card-title", text: late.name)
      expect(page).to have_link("DQOR tickets", href: "#ticket_type_#{late.id}")
      expect(page).to have_link("Rails Girls tickets", href: "#ticket_type_#{girls.id}")
      click_link "Rails Girls tickets"
      expect(page.evaluate_script("document.activeElement.id")).to eq("ticket_type_#{girls.id}")
      find("[aria-label='Add one #{girls.name}']").click
      expect(page).to have_css("[data-cart-target='total']", text: "₹350")
      expect(page).to have_field("checkout_quantities_#{late.id}", with: "0")
      expect(page).to have_css("#checkout_quantities_#{explore.id}[disabled]", visible: :all)
      find("label[for='checkout_quantities_#{explore.id}']").click
      expect(page).to have_unchecked_field("checkout_quantities_#{explore.id}", visible: :all, disabled: true)
      expect(page).to have_css("[data-cart-target='total']", text: "₹350")
      expect(Order.count).to eq(0)
      page.save_screenshot("home-ticket-choices-#{layout}.png")
    ensure
      page.current_window.resize_to(1400, 1400)
    end
  end
end
