require "rails_helper"

Capybara.register_driver(:community_groups_system) do |app|
  options = { window_size: [ 1400, 1000 ], process_timeout: 30, timeout: 20, headless: true, js_errors: true, browser_options: { "disable-back-forward-cache" => nil } }
  options[:browser_path] = ENV["CHROME_PATH"] if ENV["CHROME_PATH"].present?
  options[:browser_options].merge!("no-sandbox" => nil, "disable-dev-shm-usage" => nil) if ENV["CHROME_NO_SANDBOX"].present?
  Capybara::Cuprite::Driver.new(app, **options)
end

RSpec.describe "Owned community organizer journey", type: :system do
  before do
    driven_by :community_groups_system
    %i[organizer_platform_enabled free_event_pilot_enabled meetup_groups_enabled].each do |flag|
      allow(Rails.configuration.x).to receive(flag).and_return(true)
    end
    @console_errors = []
    page.driver.browser.on("Runtime.consoleAPICalled") { |event| @console_errors << event if event["type"] == "error" }
  end

  def sign_in_verified(user)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token: token)
  end

  it "creates a private rehearsal, publishes owned facts, opens an event and returns through Back" do
    organization = Organization.create!(name: "Synthetic local organizer", slug: "synthetic-local")
    user = create(:user_for_free_pilot)
    Membership.create!(organization: organization, user: user, role: :owner)
    event = organization.events.create!(title: "Synthetic Ruby gathering", slug: "rehearsal", status: :published, starts_at: 1.day.from_now, ends_at: 2.days.from_now, timezone: "Asia/Kolkata")
    sign_in_verified(user)
    page.driver.browser.resize(width: 390, height: 844)
    visit organizer_organization_groups_path(organization)
    click_link "Create community draft"
    fill_in "Community name", with: "Pune Ruby local rehearsal"
    fill_in "Community URL slug", with: "pune-ruby-rehearsal"
    fill_in "Short introduction", with: "Local synthetic browser rehearsal"
    fill_in "About this community", with: "This is synthetic test data and does not provision the real Pune Ruby community."
    fill_in "City", with: "Pune"
    fill_in "Country code", with: "IN"
    fill_in "Community timezone", with: "Asia/Kolkata"
    click_button "Save private draft"
    expect(page).to have_content("Draft · private")
    expect(page).not_to have_link("View public community")
    group = organization.community_groups.find_by!(slug: "pune-ruby-rehearsal")
    expect(group).to be_draft
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    click_button "Publish community"
    expect(page).to have_content("Published · public")
    select event.title, from: "Add an existing organization event"
    click_button "Add event"
    expect(event.reload.community_group_id).to eq(group.id)
    click_link "View public community"
    [ "Pune Ruby local rehearsal", "Synthetic Ruby gathering", "Asia/Kolkata" ].each { |text| expect(page).to have_content(text) }
    [ 320, 390, 768, 1440 ].each do |width|
      page.driver.browser.resize(width: width, height: 844)
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    end
    page.driver.browser.resize(width: 390, height: 844)
    page.save_screenshot(Rails.root.join("tmp/community-public-390.png"), full: true)
    page.driver.browser.keyboard.type(:tab)
    expect(page).to have_css(".skip-link:focus")
    page.driver.browser.keyboard.type(:enter)
    expect(page.evaluate_script("location.hash")).to eq("#community-main")
    click_link "Synthetic Ruby gathering"
    expect(page).to have_content("Synthetic Ruby gathering")
    page.go_back
    page.driver.wait_for_network_idle
    expect(page).to have_content("Pune Ruby local rehearsal")
    visit organizer_organization_group_path(organization, group)
    click_button "Make community private"
    expect(page).to have_content("Draft · private")
    expect(event.reload).to be_published
    expect(enqueued_jobs).to be_empty
    expect(@console_errors).to be_empty
  end

  it "denies the same signed-in organizer after membership revocation" do
    organization = Organization.create!(name: "One", slug: "one")
    user = create(:user_for_free_pilot)
    membership = Membership.create!(organization: organization, user: user, role: :owner)
    group = organization.community_groups.create!(name: "Private owned group", slug: "owned")
    sign_in_verified(user)
    visit organizer_organization_group_path(organization, group)
    expect(page).to have_content("Private owned group")
    membership.destroy!
    visit organizer_organization_group_path(organization, group)
    expect(page).not_to have_content("Private owned group")
    expect(page).not_to have_button("Publish community")
    expect(page.status_code).to eq(404)
  end
  it "wraps bounded unbroken community facts and retains usable organizer title links on mobile" do
    organization = Organization.create!(name: "O" * 120, slug: "long-organizer")
    user = create(:user_for_free_pilot)
    Membership.create!(organization: organization, user: user, role: :owner)
    group = organization.community_groups.create!(name: "N" * 120, slug: "long-facts", tagline: "T" * 160, description: "D" * 2000, city: "C" * 120, country_code: "IN", status: :published)
    sign_in_verified(user)
    [ 320, 390 ].each do |width|
      page.driver.browser.resize(width: width, height: 844)
      visit community_group_public_path(organization.slug, group.slug)
      expect(page).to have_content(group.description)
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      visit organizer_organization_groups_path(organization)
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      expect(find_link(group.name).evaluate_script("this.getBoundingClientRect().height")).to be >= 44
      click_link group.name
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
      page.save_screenshot(Rails.root.join("tmp/community-long-facts-#{width}.png"), full: true)
    end
  end
end
