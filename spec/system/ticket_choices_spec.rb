require "rails_helper"

RSpec.describe "Ticket choices", type: :system do
  let!(:early_bird) { create(:ticket_type, name: "Early Bird", slug: "conference-pass-early-bird", capacity: 0, position: 1) }
  let!(:conference) { create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", price_paise: 550_000, position: 2) }
  let!(:late_bird) { create(:ticket_type, name: "Late Bird", slug: "conference-pass-late-bird", active: false, position: 3) }
  let!(:supporter) { create(:ticket_type, name: "Supporter Pass", slug: "supporter-pass", position: 4) }
  let!(:rails_girls) { create(:ticket_type, name: "Rails Girls Pune", slug: "rails-girls-pune", price_paise: 35_000, position: 5) }
  let!(:add_on) { create(:ticket_type, name: "Explore Pune Day", slug: "explore-pune-day", requires_conference_pass: true, position: 6) }

  def activate_choice(label, ticket_type)
    find_link(label).execute_script("this.focus()")
    page.driver.browser.keyboard.type(:enter)
    expect(page).to have_current_path(tickets_store_path) { |url| url.fragment == "ticket_type_#{ticket_type.id}" }
    expect(page.evaluate_script("document.activeElement.id")).to eq("ticket_type_#{ticket_type.id}")
  end

  def fill_in_buyer
    fill_in "Buyer name", with: "Ada Lovelace"
    fill_in "Email", with: "ada@example.com"
  end

  [ [ "desktop", 1400, 1400 ], [ "mobile", 390, 844 ] ].each do |layout, width, height|
    context "on #{layout}" do
      before { page.current_window.resize_to(width, height) }
      after { page.current_window.resize_to(1400, 1400) }

      it "exposes both choices first and moves keyboard focus to their quantity controls" do
        visit tickets_store_path

        expect(page.all(".ticket-card-title").first(2).map(&:text)).to eq([ conference.name, rails_girls.name ])
        expect(page).to have_link("DQOR tickets", visible: true)
        expect(page).to have_link("Rails Girls tickets", visible: true)
        positions = page.evaluate_script(<<~JS)
          Array.from(document.querySelectorAll('.tickets-grid--primary .ticket-card')).map(card => {
            const rect = card.getBoundingClientRect()
            return { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom }
          })
        JS
        if layout == "desktop"
          expect(positions[0].fetch("top")).to eq(positions[1].fetch("top"))
          expect(positions[0].fetch("right")).to be < positions[1].fetch("left")
        else
          expect(positions[0].fetch("bottom")).to be < positions[1].fetch("top")
        end
        expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)

        activate_choice("Rails Girls tickets", rails_girls)
        page.driver.browser.keyboard.type(:tab)
        expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')")).to eq("Remove one #{rails_girls.name}")
        page.driver.browser.keyboard.type(:tab)
        expect(page.evaluate_script("document.activeElement.id")).to eq("checkout_quantities_#{rails_girls.id}")
        page.driver.browser.keyboard.type(:tab)
        expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')")).to eq("Add one #{rails_girls.name}")
        page.driver.browser.keyboard.type(:enter)
        expect(page).to have_css("[data-cart-target='total']", text: "₹350")
        expect(page).to have_no_css(".add-on-gate", visible: true)
        expect(page).to have_field("checkout_quantities_#{conference.id}", with: "0")

        activate_choice("DQOR tickets", conference)
        page.driver.browser.keyboard.type(:tab)
        expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')")).to eq("Remove one #{conference.name}")
        page.save_screenshot("ticket-choices-#{layout}.png")
      end

      it "reviews Rails Girls alone and returns to the same ticket choices with browser Back" do
        stub_request(:post, "https://api.razorpay.com/v1/orders").to_return(
          body: { id: "order_choices_#{layout}", entity: "order", amount: 35_000, currency: "INR" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
        visit tickets_store_path
        activate_choice("Rails Girls tickets", rails_girls)
        find("[aria-label='Add one #{rails_girls.name}']").click
        fill_in_buyer
        click_button "Continue to payment"

        expect(page).to have_css("h1", text: "Review your order")
        expect(page).to have_css(".summary-lines", text: "Rails Girls Pune × 1")
        expect(page).to have_css(".order-total", text: "₹350")
        expect(page).to have_button("Pay with Razorpay")
        expect(Order.sole).to be_pending
        expect(Order.sole.tickets.pluck(:ticket_type_id)).to eq([ rails_girls.id ])
        expect(Order.sole.total_paise).to eq(35_000)
        page.save_screenshot("ticket-choices-#{layout}-review.png")

        page.go_back
        expect(page).to have_css("h1", text: "Choose your pass")
        expect(page).to have_link("Rails Girls tickets")
        expect(page).to have_link("DQOR tickets")
        expect(page).to have_field("checkout_quantities_#{rails_girls.id}", with: "1")
        expect(page).to have_css("[data-cart-target='total']", text: "₹350")
      end

      it "reviews conference and Rails Girls in the existing shared cart" do
        stub_request(:post, "https://api.razorpay.com/v1/orders").to_return(
          body: { id: "order_mixed_#{layout}", entity: "order", amount: 585_000, currency: "INR" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
        visit tickets_store_path
        find("[aria-label='Add one #{conference.name}']").click
        activate_choice("Rails Girls tickets", rails_girls)
        find("[aria-label='Add one #{rails_girls.name}']").click
        expect(page).to have_css("[data-cart-target='total']", text: "₹5,850")
        expect(page).to have_no_css(".add-on-gate", visible: true)
        fill_in_buyer
        click_button "Continue to payment"

        expect(page).to have_css(".summary-lines", text: "Regular Pass × 1")
        expect(page).to have_css(".summary-lines", text: "Rails Girls Pune × 1")
        expect(page).to have_css(".order-total", text: "₹5,850")
        expect(Order.sole).to be_pending
        expect(Order.sole.tickets.pluck(:ticket_type_id)).to contain_exactly(conference.id, rails_girls.id)
        expect(Order.sole.total_paise).to eq(585_000)
      end
    end
  end
end
