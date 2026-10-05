require "rails_helper"

RSpec.describe "Organizer announcement review", type: :system do
  it "reviews and approves an immutable email at mobile width" do
    admin = create(:admin_user, password: "password123")
    preference = AnnouncementPreference.create!(email: "attendee@example.com", consented_at: Time.current)
    create(:ticket, order: create(:order, :paid), attendee_email: preference.email)
    announcement = Announcement.create!(title: "Getting ready for DQOR", body: "Doors open at 8:30.\n\nBring your ticket.")
    page.driver.browser.resize(width: 390, height: 844)
    visit new_session_path
    fill_in "email", with: admin.email
    fill_in "password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path("/avo/dashboard")
    visit announcement_campaign_path(announcement)
    expect(page).to have_content("1 recipient")
    expect(page).to have_link("Download test draft (.eml) — no email sent")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/capybara/announcement-mobile-preview.png"))
    click_on "Approve email to 1 recipient"
    expect(page).to have_content("Approved content and audience saved")
    expect(page).to have_content("Pending: 1")
    expect(page).to have_content(preference.email)
    expect(page).not_to have_button("Approve email to 1 recipient")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/capybara/announcement-mobile.png"))
  end
end
