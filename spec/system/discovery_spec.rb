require "rails_helper"

Capybara.register_driver(:discovery_system) do |app|
  options = { window_size: [ 1400, 1000 ], process_timeout: 30, timeout: 20, headless: true, js_errors: true, browser_options: { "disable-back-forward-cache" => nil } }
  options[:browser_path] = ENV["CHROME_PATH"] if ENV["CHROME_PATH"].present?
  options[:browser_options].merge!("no-sandbox" => nil, "disable-dev-shm-usage" => nil) if ENV["CHROME_NO_SANDBOX"].present?
  Capybara::Cuprite::Driver.new(app, **options)
end

RSpec.describe "Event discovery journey", type: :system do
  before do
    driven_by :discovery_system
    @console_errors = []
    page.driver.browser.on("Runtime.consoleAPICalled") { |event| @console_errors << event if event["type"] == "error" }
    allow(Rails.configuration.x).to receive(:event_discovery_enabled).and_return(true)
    import_discovery(records: [ discovery_record(registration_url: "https://example.com/register") ])
    import_discovery(source_key: "other", records: [ discovery_record(external_id: "london", canonical_url: "https://example.com/london", title: "React community gathering", city: "London", country_code: "GB", topics: [ "react" ]) ])
    import_discovery(source_key: "past", records: [ discovery_record(external_id: "historic", canonical_url: "https://example.com/historic", title: "Pune Ruby February 2025", starts_on: "2025-02-01") ])
  end

  it "searches, filters, opens original-source details and returns through Back on mobile" do
    page.driver.browser.resize(width: 390, height: 844)
    visit discovery_listings_path
    expect(page).to have_content("Ruby community gathering")
    expect(page.evaluate_script("(() => { const rows = [...document.querySelectorAll('.event-card')].map(e => e.getBoundingClientRect()); return rows[0].bottom <= innerHeight && rows[1].top < innerHeight; })()")).to be(true)
    expect(page.evaluate_script("[...document.querySelectorAll('.event-card h2 a')].every(e => e.getBoundingClientRect().height >= 44)")).to be(true)
    [ 320, 768, 1440, 390 ].each do |width|
      page.driver.browser.resize(width: width, height: 844)
      expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    end
    page.driver.browser.keyboard.type(:tab)
    expect(page).to have_css(".skip-link:focus")
    page.driver.browser.keyboard.type(:enter)
    expect(page.evaluate_script("location.hash")).to eq("#directory-main")
    expect(page).not_to have_content("Pune Ruby February 2025")
    fill_in "Search events or cities", with: "Pune"
    select "Pune, India", from: "Where"
    select "Ruby", from: "Topic"
    click_button "Find events"
    expect(page).to have_content("1 event")
    click_link "Ruby community gathering"
    expect(page).to have_content("Time not published")
    expect(page).to have_link("View on example.com ↗", href: "https://example.com/register")
    expect(page).not_to have_button("Register free")
    page.save_screenshot(Rails.root.join("tmp/discovery-detail-mobile.png"), full: true)
    page.go_back
    page.driver.wait_for_network_idle
    expect(page).to have_current_path(%r{\A/discover\?})
    expect(page).to have_field("Search events or cities", with: "Pune")
    select "Past events", from: "When"
    click_button "Find events"
    expect(page).to have_content("Pune Ruby February 2025")
    page.driver.browser.resize(width: 320, height: 844)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/discovery-directory-mobile.png"), full: true)
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.discovery-hero')).animationName")).to eq("none")
    expect(@console_errors).to be_empty
  ensure
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [])
  end
end
