require "rails_helper"

RSpec.describe "Private community first-event journey", type: :system do
  before do
    %i[organizer_platform_enabled free_event_pilot_enabled meetup_groups_enabled].each do |flag|
      allow(Rails.configuration.x).to receive(flag).and_return(true)
    end
    @console_errors = []
    page.driver.browser.on("Runtime.consoleAPICalled") { |event| @console_errors << event if event["type"] == "error" }
  end

  it "starts a group draft, retries invalid event details, returns through Back and denies a revoked organizer at 390px" do
    organization = Organization.create!(name: "Synthetic local organizer", slug: "synthetic-local")
    user = create(:user_for_free_pilot)
    membership = Membership.create!(organization: organization, user: user, role: :owner)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token: token)
    page.driver.browser.resize(width: 390, height: 844)
    visit organizer_organization_events_path(organization)
    click_link "Organization communities"
    click_link "Create community draft"
    fill_in "Community name", with: "Synthetic Ruby rehearsal"
    fill_in "Community URL slug", with: "synthetic-ruby"
    fill_in "Community timezone", with: "Asia/Kolkata"
    click_button "Save private draft"
    expect(page).to have_content("Draft · private")
    expect(page).not_to have_button("Publish community")
    group = organization.community_groups.find_by!(slug: "synthetic-ruby")
    expect(group).to be_draft
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    click_link "Create community event draft"
    expect(page).to have_content("Synthetic Ruby rehearsal")
    expect(page).to have_field("Display timezone", with: "Asia/Kolkata")
    fill_in "Title", with: "Synthetic first gathering"
    fill_in "Event URL name", with: "bad_slug"
    click_button "Create Event"
    expect(page).to have_content("Slug is invalid")
    expect(page).to have_field("Title", with: "Synthetic first gathering")
    expect(page).to have_field("Event URL name", with: "bad_slug")
    expect(page).to have_field("Display timezone", with: "Asia/Kolkata")
    expect(group.events.count).to eq(0)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/capybara/community-first-event-invalid-390.png"), full: true)
    fill_in "Event URL name", with: "synthetic-first"
    click_button "Create Event"
    expect(page).to have_content("Community event draft created.")
    expect(page).to have_link("Synthetic first gathering")
    event = group.events.find_by!(slug: "synthetic-first")
    expect(event).to have_attributes(status: "draft", organization_id: organization.id, timezone: "Asia/Kolkata")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/capybara/community-first-event-linked-390.png"), full: true)
    click_link "Synthetic first gathering"
    expect(page).to have_content("Only your team can view this draft.")
    page.go_back
    expect(page).to have_content("Synthetic Ruby rehearsal")
    expect(page).to have_link("Synthetic first gathering")
    membership.destroy!
    click_link "Create community event draft"
    expect(page.status_code).to eq(404)
    expect(page).not_to have_content("Synthetic Ruby rehearsal")
    expect(group.events.count).to eq(1)
    expect(event.reload).to be_draft
    expect(enqueued_jobs).to be_empty
    expect(@console_errors).to be_empty
  end
end
