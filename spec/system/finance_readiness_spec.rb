require "rails_helper"

RSpec.describe "Finance readiness screens", type: :system do
  it "keeps personal checkout short and reveals required billing for high-value selections" do
    ticket_type = create(:ticket_type, name: "High-value Test Pass", price_paise: 5_000_000, capacity: 10)
    create(:coupon, code: "BELOWLIMIT", ticket_type:, discount_paise: 1, percent: nil)
    visit tickets_store_path
    expect(page).to have_no_css("details.gst-details[open]")
    find("[aria-label='Add one #{ticket_type.name}']").click
    expect(page).to have_css("details.gst-details[open]")
    expect(page).to have_css("#checkout_billing_address[required]")
    expect(find_field("State or union territory name")[:required]).to be(true)
    fill_in "Coupon code", with: "BELOWLIMIT"
    expect(page).to have_content("Coupon BELOWLIMIT applied")
    expect(page).to have_no_css("#checkout_billing_address[required]")
    find_field("Coupon code").send_keys(*Array.new(10, :backspace))
    expect(page).to have_css("#checkout_billing_address[required]")
    find("[aria-label='Remove one #{ticket_type.name}']").click
    expect(page).to have_no_css("#checkout_billing_address[required]")
    page.save_screenshot(Rails.root.join("tmp/finance-billing-checkout.png"))
  end

  it "shows blank policy drafts and the private remediation queue to an administrator" do
    admin = create(:admin_user, password: "test-password-123")
    order = create(:order, :paid, metadata: { "invoice_pending_reason" => "InvoicePolicy::NotConfigured" })
    visit new_session_path
    fill_in "Email address", with: admin.email
    fill_in "Password", with: "test-password-123"
    click_button "Sign in"
    expect(page).to have_current_path("/avo/dashboard")
    visit new_finance_policy_path
    expect(find_field("Seller legal name").value).to eq("")
    expect(page).to have_content("Approval is not tax-registry verification")
    page.save_screenshot(Rails.root.join("tmp/finance-policy-draft.png"))
    visit finance_document_path(order)
    expect(page).to have_content("Buyer billing facts")
    click_button "Create private buyer follow-up link"
    expect(page).to have_field("Private billing follow-up link")
    page.save_screenshot(Rails.root.join("tmp/finance-document-queue.png"))
    page.driver.resize(390, 844)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
  end
end
