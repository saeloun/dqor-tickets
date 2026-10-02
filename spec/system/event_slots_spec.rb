require "rails_helper"

RSpec.describe "Mobile slot views", type: :system do
  it "shows purpose prominently and verified own status without overflow" do
    operator = create(:admin_user, password: "password123")
    slot = EventSlot.create!(name: "Synthetic Day1 food", starts_at: Time.utc(2026, 10, 8, 6), ends_at: Time.utc(2026, 10, 8, 9))
    page.driver.browser.resize(width: 375, height: 812)
    visit event_slot_path(slot)
    fill_in "email", with: operator.email
    fill_in "password", with: "password123"
    click_button "Sign in"
    expect(page).to have_content("Scanning: Synthetic Day1 food")
    expect(page).to have_content("Draft — redemption disabled")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    user = User.create!(email: "mobile@example.test")
    create(:ticket, order: create(:order, :paid), attendee_email: user.email, checked_in_at: { "2026-10-08" => "2026-10-08T07:00:00Z" })
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token: token)
    visit account_redemptions_path
    expect(page).to have_content("2026-10-08T07:00:00Z")
    page.execute_script("window.dispatchEvent(new Event('offline'))")
    expect(page).to have_content("may be stale")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
  end
end
