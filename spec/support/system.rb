require "capybara/rspec"
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  options = {
    window_size: [ 1400, 1400 ],
    process_timeout: 30,
    timeout: 20,
    headless: true,
    js_errors: true
  }
  options[:browser_path] = ENV["CHROME_PATH"] if ENV["CHROME_PATH"].present?
  options[:browser_options] = { "no-sandbox": nil, "disable-dev-shm-usage": nil } if ENV["CHROME_NO_SANDBOX"].present?

  Capybara::Cuprite::Driver.new(app, **options)
end

Capybara.default_driver = :rack_test
Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5
Capybara.server = :puma, { Silent: true }
Capybara.save_path = Rails.root.join("tmp/capybara")

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :cuprite }
end
