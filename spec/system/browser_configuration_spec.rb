require "rails_helper"

RSpec.describe "System browser configuration", type: :system do
  it "retains configured Ferrum options after Rails sets up the system driver" do
    expect(driver.name).to eq(:cuprite_system)
    expect(Capybara.current_driver).to eq(:cuprite_system)
    configured_driver = Capybara.drivers[Capybara.current_driver].call(Rails.application)
    options = Ferrum::Browser::Options.new(configured_driver.options)

    expect(options.process_timeout).to eq(30)
    expect(options.timeout).to eq(20)
    expect(options.window_size).to eq([ 1400, 1400 ])
    expect(options.headless).to be(true)
    expect(options.js_errors).to be(true)
    expect(Capybara.default_max_wait_time).to eq(5)
  end

  it "retains the CI Chromium path and flags after the actual driven_by registration path" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("CHROME_PATH").and_return("/usr/bin/chromium-browser")
    allow(ENV).to receive(:[]).with("CHROME_NO_SANDBOX").and_return("1")
    driven_by :cuprite_system
    configured_driver = Capybara.drivers[Capybara.current_driver].call(Rails.application)
    options = Ferrum::Browser::Options.new(configured_driver.options)

    expect(options.browser_path).to eq("/usr/bin/chromium-browser")
    expect(options.browser_options).to include("no-sandbox": nil, "disable-dev-shm-usage": nil)
    expect(options.process_timeout).to eq(30)
    expect(options.js_errors).to be(true)
  end
end
