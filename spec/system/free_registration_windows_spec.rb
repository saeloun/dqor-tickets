require "rails_helper"

RSpec.describe "Registration window journey", type: :system do
  it "previews private local times and renders upcoming, available, sold out and closed on mobile" do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_registration_windows_enabled).and_return(true)
    travel_to Time.utc(2027, 1, 1, 10)
    owner = create(:user_for_free_pilot, name: "Synthetic Organizer")
    attendee = create(:user_for_free_pilot, name: "Synthetic Attendee")
    org = Organization.create!(name: "Ruby Community", slug: "window-journey")
    Membership.create!(organization: org, user: owner, role: :owner)
    event = org.events.create!(title: "An evening with Ruby", slug: "ruby-evening", timezone: "Asia/Kolkata", status: :published, starts_at: Time.utc(2027, 1, 2, 12), ends_at: Time.utc(2027, 1, 2, 16))
    type = create(:ticket_type, name: "Community admission", event_id: event.id, price_paise: 0, hidden: true, active: false, capacity: 1, free_published_at: Time.current)
    visit account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(owner.id, purpose: :account_magic_link, expires_in: 30.minutes))
    visit free_event_window_path(org, event, type)
    page.driver.browser.resize(width: 390, height: 844)
    fill_in "Registration opens (optional)", with: "2027-01-01T16:00"
    fill_in "Registration closes (optional)", with: "2027-01-02T20:00"
    click_button "Save window draft"
    fill_in "Registration closes (optional)", with: "2027-01-01T15:00"
    click_button "Save window draft"
    expect(page).to have_content("Registration must close after it opens")
    expect(page).to have_field("Registration opens (optional)", with: "2027-01-01T16:00")
    expect(page).to have_field("Registration closes (optional)", with: "2027-01-01T15:00")
    page.save_screenshot(Rails.root.join("tmp/windows-organizer-error-mobile.png"), full: true)
    fill_in "Registration closes (optional)", with: "2027-01-02T20:00"
    click_button "Save window draft"
    expect(page).to have_content("Saved draft preview · Private")
    expect(page).to have_content("If published now: Upcoming")
    expect(page).to have_content("+05:30")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/windows-organizer-mobile.png"), full: true)
    click_button "Publish registration window"
    expect(page).to have_content("Registration window published")
    visit published_event_path(org.slug, event.slug)
    expect(page).to have_content("Upcoming")
    expect(page).not_to have_button("Register free")
    page.save_screenshot(Rails.root.join("tmp/windows-upcoming-mobile.png"), full: true)
    travel_to Time.utc(2027, 1, 1, 10, 30)
    visit published_event_path(org.slug, event.slug)
    expect(page).to have_button("Register free")
    expect(page).to have_content("Available")
    page.save_screenshot(Rails.root.join("tmp/windows-available-mobile.png"), full: true)
    FreeEvents::Register.call(user: attendee, event_id: event.id, ticket_type_id: type.id)
    visit published_event_path(org.slug, event.slug)
    expect(page).to have_content("Sold out")
    expect(page).not_to have_button("Register free")
    page.save_screenshot(Rails.root.join("tmp/windows-sold-out-mobile.png"), full: true)
    travel_to Time.utc(2027, 1, 2, 14, 30)
    page.driver.browser.resize(width: 320, height: 740)
    visit published_event_path(org.slug, event.slug)
    expect(page).to have_content("Closed")
    expect(page).to have_link("View your ticket")
    expect(page).not_to have_button("Register free")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/windows-closed-320.png"), full: true)
    expect(enqueued_jobs).to be_empty
  ensure
    travel_back
  end
end
