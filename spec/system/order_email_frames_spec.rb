require "rails_helper"

RSpec.describe "Order email frame updates", type: :system do
  around do |example|
    original_app = Capybara.app
    Capybara.app = OrderEmailObfuscation.new(original_app)
    example.run
  ensure
    Capybara.reset_sessions!
    Capybara.app = original_app
  end

  before do
    driven_by :order_email_obfuscation
    allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")
  end

  def expect_readable_emails(order, ticket, journey)
    expect(page).to have_css("#order_status[complete]:not([busy])")
    if page.has_css?("#order_status a.__cf_email__")
      page.save_screenshot("order-email-#{journey}-obfuscated.png", full: true)
      find("#order_status a.__cf_email__", match: :first).click
      expect(page).to have_css("#order_status .turbo-frame-error", text: "Content missing")
      expect(page.driver.app.protection_requests).to include("order_status")
      puts "Observed #{journey}: protected email click returned a response without order_status and displayed Content missing"
      page.save_screenshot("order-email-#{journey}-content-missing.png", full: true)
    end

    expect(page).to have_no_content("Content missing")
    within "#order_status" do
      expect(page).to have_content("Your tickets are confirmed")
      expect(page).to have_content(order.email)
      expect(page).to have_content(ticket.attendee_email)
      expect(page).to have_no_css("a.__cf_email__")
      expect(page).to have_no_css("a[href*='/cdn-cgi/l/email-protection']")
      expect(page).to have_button("Update ticket")
    end
    expect(page.driver.app.protection_requests).to be_empty
    page.save_screenshot("order-email-#{journey}-readable.png", full: true)
  end

  it "keeps buyer and attendee emails readable after the real payment poll reloads the frame" do
    order = create(:order, email: "buyer@example.test")
    ticket = create(:ticket, order:, attendee_email: "attendee@example.test")
    visit order_path(order.code)
    expect(page).to have_content("Confirming your payment")
    page.execute_script("document.body.dataset.initialDocument = 'retained'")

    order.update!(status: :paid)

    expect(page).to have_content("Your tickets are confirmed", wait: 12)
    expect(page.evaluate_script("document.body.dataset.initialDocument")).to eq("retained")
    expect_readable_emails(order, ticket, "poll")
    expect(ticket.reload.attendee_email).to eq("attendee@example.test")
  end

  it "keeps buyer and attendee emails readable after assignment redirects inside the frame" do
    order = create(:order, :paid, email: "buyer@example.test")
    ticket = create(:ticket, order:, attendee_name: nil, attendee_email: nil)
    visit order_path(order.code)
    expect(page).to have_content(order.email)
    expect(page).to have_no_css("a.__cf_email__")
    page.execute_script("document.body.dataset.initialDocument = 'retained'")

    within "form.assignment-form" do
      fill_in "Attendee name", with: "Synthetic Attendee"
      fill_in "Attendee email", with: "attendee@example.test"
      click_button "Assign this ticket"
    end

    expect(page).to have_content("Ticket assigned to Synthetic Attendee.")
    expect(page.evaluate_script("document.body.dataset.initialDocument")).to eq("retained")
    expect_readable_emails(order, ticket.reload, "assignment")
    expect(ticket.attendee_name).to eq("Synthetic Attendee")
  end
end
