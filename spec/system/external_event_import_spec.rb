require "rails_helper"

RSpec.describe "External event draft creation", type: :system do
  let!(:organization) { Organization.create!(name: "Pune Ruby Meetup", slug: "pune-ruby") }
  let!(:user) { User.create!(email: "browser-importer@example.com") }
  let!(:membership) { Membership.create!(organization: organization, user: user, role: :owner) }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
  end

  it "creates the approved calendar draft and publishes escaped metadata without private notes" do
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token: token)
    visit new_organizer_organization_event_path(organization)
    fill_in "Title", with: "Ruby Meetup X AI Collective: Expert Insights & Hands-On Workshop"
    fill_in "Event URL name", with: "ruby-ai-october"
    fill_in "Display timezone", with: "Asia/Kolkata"
    fill_in "Start (UTC)", with: "2026-10-24T04:30"
    fill_in "End (UTC)", with: "2026-10-24T07:30"
    fill_in "Description", with: "Ruby developers, AI explorers and first-time speakers welcome."
    fill_in "Venue name", with: "Pattern Technologies India Private Limited"
    fill_in "Venue address", with: "Kalyani Nagar, Pune"
    fill_in "Public source URL", with: "https://luma.com/48awjqkg"
    fill_in "External registration URL", with: "https://luma.com/48awjqkg"
    fill_in "Call for speakers URL", with: "https://forms.gle/6ZazdAJ2iJ8QFm7i6"
    fill_in "Topics", with: "Ruby, Ruby on Rails, AI"
    fill_in "Private import notes", with: "Poster11AM–1PM; bodyOctober17; checkin09:30; agendaafter13:00. Owner approved calendar24Oct10AM–1PM."
    click_button "Create Event"
    expect(page).to have_text("Draft created.")
    expect(page).to have_text("10:00 AM")
    expect(page).to have_text("1:00 PM")
    expect(page).to have_text("Poster11AM–1PM; bodyOctober17")
    page.save_screenshot(Rails.root.join("tmp/capybara/external-event-private-draft.png"))
    click_button "Publish event"
    click_link "View public event"
    expect(page).to have_text("Pattern Technologies India Private Limited")
    expect(page).to have_link("View external registration", href: "https://luma.com/48awjqkg")
    expect(page).to have_link("Call for speakers", href: "https://forms.gle/6ZazdAJ2iJ8QFm7i6")
    [ "Poster11AM", "bodyOctober17", "Private import notes" ].each { |text| expect(page).not_to have_text(text) }
    expect(page).not_to have_text("Register free")
    page.save_screenshot(Rails.root.join("tmp/capybara/external-event-public.png"))
    expect(organization.events.count).to eq(1)
  end
end
