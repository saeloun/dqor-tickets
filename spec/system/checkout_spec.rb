require "rails_helper"

RSpec.describe "Checkout storefront", type: :system do
  def card_for(name)
    find(".ticket-card", text: name)
  end

  def quantity_field_for(ticket_type)
    "checkout_quantities_#{ticket_type.id}"
  end

  def add_one(ticket_type)
    find("[aria-label='Add one #{ticket_type.name}']").click
  end

  def remove_one(ticket_type)
    find("[aria-label='Remove one #{ticket_type.name}']").click
  end

  def insert_csrf_meta_tag
    page.execute_script(<<~JS)
      const meta = document.createElement("meta")
      meta.name = "csrf-token"
      meta.content = "test-token"
      document.head.appendChild(meta)
    JS
  end

  def fill_in_buyer
    fill_in "Buyer name", with: "Ada Lovelace"
    fill_in "Email", with: "ada@example.com"
    fill_in "Phone", with: "9999999999"
  end

  it "lists every visible ticket type with its price, sale state and availability" do
    on_sale = create(:ticket_type, name: "Early Bird", slug: "conference-pass-early-bird", price_paise: 350_000, capacity: 30, max_per_order: 25, position: 1)
    sold_out = create(:ticket_type, name: "Blind Bird", slug: "conference-pass-blind-bird", capacity: 1, position: 2)
    coming_soon = create(:ticket_type, name: "Late Bird", slug: "conference-pass-late-bird", active: false, position: 3)
    unlimited = create(:ticket_type, name: "Community Pass", slug: "conference-pass-community", capacity: nil, max_per_order: 3, position: 4)
    create(:ticket_type, name: "Secret Sponsor Pass", hidden: true, position: 5)
    create_list(:ticket, 7, ticket_type: on_sale, order: create(:order, :paid))
    create(:ticket, ticket_type: sold_out, order: create(:order, :paid))

    visit root_path

    expect(page).to have_css("h1", text: "Choose your conference pass")

    expect(page).to have_css(".ticket-card--on-sale", text: on_sale.name)
    expect(page).to have_css(".ticket-card--sold-out", text: sold_out.name)
    expect(page).to have_css(".ticket-card--coming-soon", text: coming_soon.name)

    within card_for(on_sale.name) do
      expect(page).to have_css(".ticket-state-badge", text: "ON SALE")
      expect(page).to have_css(".ticket-price-amount", text: "₹3,500")
      expect(page).to have_css(".ticket-price-note", text: "GST included")
      expect(page).to have_css(".ticket-availability", text: "23 of 30 left")
      expect(page).to have_css(".quantity-stepper")
    end

    within card_for(sold_out.name) do
      expect(page).to have_css(".ticket-state-badge", text: "SOLD OUT")
      expect(page).to have_css(".ticket-price-amount", text: "Sold Out")
      expect(page).to have_css(".ticket-availability.ticket-availability--low", text: "0 of 1 left")
      expect(page).to have_css(".ticket-unavailable", text: "This tier has sold out.")
      expect(page).to have_no_css(".quantity-stepper")
    end

    within card_for(coming_soon.name) do
      expect(page).to have_css(".ticket-state-badge", text: "COMING SOON")
      expect(page).to have_css(".ticket-price-amount", text: "Coming Soon")
      expect(page).to have_css(".ticket-unavailable", text: "Sales open soon.")
      expect(page).to have_no_css(".quantity-stepper")
    end

    within card_for(unlimited.name) do
      expect(page).to have_css(".ticket-state-badge", text: "ON SALE")
      expect(page).to have_no_css(".ticket-availability")
    end

    expect(page).to have_no_content("Secret Sponsor Pass")
    expect(page).to have_css(".ticket-card", count: 4)
    expect(page.all(".ticket-card-title").map(&:text)).to eq([ on_sale, sold_out, coming_soon, unlimited ].map(&:name))
  end

  it "caps the quantity input at the remaining stock" do
    scarce = create(:ticket_type, name: "Scarce Pass", slug: "conference-pass-scarce", capacity: 30, max_per_order: 25, position: 1)
    create_list(:ticket, 7, ticket_type: scarce, order: create(:order, :paid))
    capped = create(:ticket_type, name: "Capped Pass", slug: "conference-pass-capped", capacity: nil, max_per_order: 3, position: 2)

    visit root_path

    expect(find_field(quantity_field_for(scarce))[:max]).to eq("23")
    expect(find_field(quantity_field_for(capped))[:max]).to eq("3")
    expect(find_field(quantity_field_for(scarce))[:min]).to eq("0")
  end

  it "counts unexpired pending orders against availability but releases expired ones" do
    ticket_type = create(:ticket_type, name: "Reserved Pass", slug: "conference-pass-reserved", capacity: 10, position: 1)
    create_list(:ticket, 2, ticket_type:, order: create(:order, expires_at: 20.minutes.from_now))
    create(:ticket, ticket_type:, order: create(:order, expires_at: 5.minutes.ago))

    visit root_path

    within card_for(ticket_type.name) do
      expect(page).to have_css(".ticket-availability", text: "8 of 10 left")
    end
  end

  it "adds up the selected tickets in the order total as the stepper is used" do
    ticket_type = create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", price_paise: 350_000, capacity: 2, position: 1)

    visit root_path

    expect(page).to have_css("[data-cart-target='total']", text: "₹0")

    add_one(ticket_type)
    expect(page).to have_field(quantity_field_for(ticket_type), with: "1")
    expect(page).to have_css("[data-cart-target='total']", text: "₹3,500")

    add_one(ticket_type)
    add_one(ticket_type)
    expect(page).to have_field(quantity_field_for(ticket_type), with: "2")
    expect(page).to have_css("[data-cart-target='total']", text: "₹7,000")

    remove_one(ticket_type)
    expect(page).to have_field(quantity_field_for(ticket_type), with: "1")
    expect(page).to have_css("[data-cart-target='total']", text: "₹3,500")

    remove_one(ticket_type)
    remove_one(ticket_type)
    expect(page).to have_field(quantity_field_for(ticket_type), with: "0")
    expect(page).to have_css("[data-cart-target='total']", text: "₹0")
  end

  it "totals a mixed cart of conference passes and the Explore Pune Day add-on" do
    conference = create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", price_paise: 350_000, capacity: 10, position: 1)
    add_on = create(:ticket_type, name: "Explore Pune Day", slug: "explore-pune-day", price_paise: 250_000, capacity: 50, requires_conference_pass: true, position: 2)

    visit root_path

    add_one(conference)
    check quantity_field_for(add_on), allow_label_click: true

    expect(page).to have_css("[data-cart-target='total']", text: "₹6,000")
  end

  it "reveals the Explore Pune Day gate only for a standalone add-on" do
    conference = create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", price_paise: 350_000, capacity: 10, position: 1)
    add_on = create(:ticket_type, name: "Explore Pune Day", slug: "explore-pune-day", price_paise: 250_000, capacity: 50, requires_conference_pass: true, position: 2)

    visit root_path

    expect(page).to have_css(".add-on-gate", visible: :hidden)
    expect(page).to have_no_css(".add-on-gate", visible: :visible)

    check quantity_field_for(add_on), allow_label_click: true

    expect(page).to have_css(".add-on-gate", visible: :visible)
    within ".add-on-gate" do
      expect(page).to have_content("Already have a conference pass?")
      expect(page).to have_field("Paid order code")
      expect(page).to have_field("Paid order email")
      expect(find_field("Paid order code")[:maxlength]).to eq("8")
      expect(find_field("Paid order email")[:type]).to eq("email")
    end

    add_one(conference)
    expect(page).to have_no_css(".add-on-gate", visible: :visible)

    remove_one(conference)
    expect(page).to have_css(".add-on-gate", visible: :visible)

    uncheck quantity_field_for(add_on), allow_label_click: true
    expect(page).to have_no_css(".add-on-gate", visible: :visible)
  end

  it "labels the add-on card and disables its checkbox before sales open" do
    add_on = create(:ticket_type, name: "Explore Pune Day", slug: "explore-pune-day", active: false, requires_conference_pass: true, position: 1)

    visit root_path

    within card_for(add_on.name) do
      expect(page).to have_css(".ticket-type-badge--retreat", text: "EXPLORE PUNE DAY")
      expect(page).to have_css(".ticket-state-badge", text: "COMING SOON")
      expect(page).to have_content("October 11, 2026 (Sunday)")
      expect(page).to have_content("Guided tour around Pune")
    end

    expect(page).to have_field(quantity_field_for(add_on), disabled: true, visible: :all)
  end

  it "offers a coupon code field that starts without a message" do
    create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", position: 1)

    visit root_path

    expect(page).to have_field("Coupon code", with: "", type: "text")
    expect(find_field("Coupon code")[:placeholder]).to eq("Optional")
    expect(page).to have_css(".coupon-message", visible: :hidden)
    expect(page).to have_no_css(".coupon-message", visible: :visible)
  end

  it "previews a valid coupon against the live cart" do
    ticket_type = create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", price_paise: 350_000, capacity: 5, position: 1)
    create(:coupon, code: "PUNE500", discount_paise: 50_000, ticket_type:)

    visit root_path
    insert_csrf_meta_tag
    add_one(ticket_type)
    fill_in "Coupon code", with: "PUNE500"

    expect(page).to have_css(".coupon-message.coupon-message--applied", text: "Coupon PUNE500 applied · −₹500")
    expect(page).to have_css("[data-cart-target='total']", text: "₹3,000")
  end

  it "previews an unknown coupon as invalid and keeps the undiscounted total" do
    ticket_type = create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", price_paise: 350_000, capacity: 5, position: 1)

    visit root_path
    insert_csrf_meta_tag
    add_one(ticket_type)
    fill_in "Coupon code", with: "NOSUCHCODE"

    expect(page).to have_css(".coupon-message.coupon-message--invalid", text: "Coupon not valid")
    expect(page).to have_css("[data-cart-target='total']", text: "₹3,500")
  end

  it "blocks submission client side until the required buyer fields are filled" do
    ticket_type = create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", capacity: 5, position: 1)

    visit root_path
    add_one(ticket_type)
    click_button "Continue to payment"

    expect(page).to have_css("h1", text: "Choose your conference pass")
    expect(page.evaluate_script("document.getElementById('checkout_buyer_name').validity.valueMissing")).to be(true)
    expect(page.evaluate_script("document.getElementById('checkout_email').validity.valueMissing")).to be(true)
    expect(Order.count).to eq(0)

    fill_in "Buyer name", with: "Ada Lovelace"
    fill_in "Email", with: "not-an-email"

    expect(page.evaluate_script("document.getElementById('checkout_email').validity.typeMismatch")).to be(true)
  end

  it "re-renders the storefront with an alert when no tickets are selected" do
    ticket_type = create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", capacity: 5, position: 1)

    visit root_path
    fill_in_buyer
    click_button "Continue to payment"

    expect(page).to have_css(".alert", text: "select at least one ticket")
    expect(page).to have_css(".ticket-card-title", text: ticket_type.name)
    expect(Order.count).to eq(0)
  end

  it "rejects a standalone Explore Pune Day add-on without a paid conference order" do
    add_on = create(:ticket_type, name: "Explore Pune Day", slug: "explore-pune-day", price_paise: 250_000, capacity: 50, requires_conference_pass: true, position: 1)

    visit root_path
    check quantity_field_for(add_on), allow_label_click: true
    fill_in_buyer
    fill_in "Paid order code", with: "NOPE1234"
    fill_in "Paid order email", with: "someone@example.com"
    click_button "Continue to payment"

    expect(page).to have_css(".alert", text: "a paid conference pass is required")
    expect(Order.count).to eq(0)
  end

  it "rejects a coupon that does not apply to the selected tickets" do
    ticket_type = create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", capacity: 5, position: 1)
    other = create(:ticket_type, name: "Workshop Pass", slug: "conference-pass-workshop", capacity: 5, position: 2)
    create(:coupon, code: "WORKSHOP50", discount_paise: 50_000, ticket_type: other)

    visit root_path
    add_one(ticket_type)
    fill_in_buyer
    fill_in "Coupon code", with: "WORKSHOP50"
    click_button "Continue to payment"

    expect(page).to have_css(".alert", text: "Coupon does not apply to these tickets")
    expect(Order.count).to eq(0)
  end

  it "rejects an unknown coupon code" do
    ticket_type = create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", capacity: 5, position: 1)

    visit root_path
    add_one(ticket_type)
    fill_in_buyer
    fill_in "Coupon code", with: "NOSUCHCODE"
    click_button "Continue to payment"

    expect(page).to have_css(".alert", text: "Coupon not valid")
    expect(Order.count).to eq(0)
  end

  it "completes a fully discounted order without touching Razorpay" do
    ticket_type = create(:ticket_type, name: "Regular Pass", slug: "conference-pass-regular", price_paise: 350_000, capacity: 5, position: 1)
    create(:coupon, code: "ONTHEHOUSE", discount_paise: nil, percent: 100, ticket_type:)

    visit root_path
    add_one(ticket_type)
    fill_in_buyer
    fill_in "Coupon code", with: "ONTHEHOUSE"
    click_button "Continue to payment"

    expect(page).to have_css("h1", text: "Review your order")
    expect(page).to have_css(".status-card--paid", text: "Confirmed")
    expect(page).to have_css(".summary-discount", text: "−₹3,500")
    expect(page).to have_css(".order-total", text: "₹0")
    expect(page).to have_no_css(".payment-button")

    order = Order.sole
    expect(order.total_paise).to eq(0)
    expect(order).to be_paid
    expect(order.razorpay_order_id).to be_nil
    expect(page).to have_link("View tickets", href: order_path(order.code))
  end
end
