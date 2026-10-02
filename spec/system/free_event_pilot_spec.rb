require "rails_helper"

RSpec.describe "Free event pilot journey", type: :system do
  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
  end

  def sign_in_verified(user)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token: token)
    expect(page).to have_current_path(/\A\/(?:account|free\/tickets)/)
  end

  it "creates, publishes, registers, retrieves, checks in, and exports a synthetic free event" do
    owner = create(:user_for_free_pilot, name: "Synthetic Organizer")
    attendee = create(:user_for_free_pilot, name: "Synthetic Attendee")
    sign_in_verified(owner)
    visit new_free_organization_path
    fill_in "Name", with: "Demo Ruby Community"
    fill_in "URL name", with: "demo-ruby"
    click_button "Create organization"
    click_link "Create draft event"
    page.driver.browser.resize(width: 390, height: 844)
    page.save_screenshot(Rails.root.join("tmp/free-pilot-create-mobile.png"))
    fill_in "Title", with: "Free Ruby Meetup"
    fill_in "Slug", with: "free-meetup"
    fill_in "IANA timezone (for display)", with: "UTC"
    fill_in "Start (UTC)", with: 1.hour.ago.utc.strftime("%Y-%m-%dT%H:%M")
    fill_in "End (UTC)", with: 1.day.from_now.utc.strftime("%Y-%m-%dT%H:%M")
    click_button "Create Event"
    click_button "Publish event"
    expect(page).to have_content("Status: published")
    click_link "Open free registration"
    fill_in "Ticket name", with: "Community admission"
    fill_in "Capacity", with: "0"
    page.execute_script("document.querySelector('input[type=number]').removeAttribute('min')")
    click_button "Publish free tickets"
    expect(page).to have_content("Capacity must be between")
    expect(page).to have_field("Ticket name", with: "Community admission")
    fill_in "Capacity", with: "5"
    click_button "Publish free tickets"
    expect(page).to have_content("Free registration is open")
    organization = Organization.find_by!(slug: "demo-ruby")
    event = organization.events.find_by!(slug: "free-meetup")
    sign_in_verified(attendee)
    visit published_event_path(organization.slug, event.slug)
    click_button "Register free"
    expect(page).to have_content("You’re registered")
    expect(page).to have_content("Synthetic Attendee")
    expect(page).to have_content("No confirmation email is sent")
    page.driver.browser.resize(width: 1400, height: 1000)
    page.save_screenshot(Rails.root.join("tmp/free-pilot-ticket.png"))
    page.driver.browser.resize(width: 390, height: 844)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/free-pilot-ticket-mobile.png"))
    page.driver.browser.resize(width: 1400, height: 1400)
    click_link "All my free tickets"
    click_link "Free Ruby Meetup"
    expect(page).to have_content("Free admission")
    sign_in_verified(owner)
    visit free_event_attendees_path(organization, event)
    expect(page).to have_content(attendee.email)
    page.driver.browser.resize(width: 390, height: 844)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/free-pilot-checkin-mobile.png"))
    ticket = Ticket.find_by!(event_id: event.id)
    click_button "Check in ticket ##{ticket.id}"
    expect(page).to have_content("Attendee checked in")
    expect(page).to have_link("Download attendee CSV")
    page.save_screenshot(Rails.root.join("tmp/free-pilot-organizer.png"))
    expect(FreeCheckin.find_by!(ticket: ticket).operator).to eq(owner)
    expect(Invoice.count).to eq(0)
    expect(PaymentEvent.count).to eq(0)
    expect(enqueued_jobs).to be_empty
  end
end
