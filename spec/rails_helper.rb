ENV["RAILS_ENV"] ||= "test"
ENV["RAZORPAY_KEY_ID"] = "rzp_test_key"
ENV["RAZORPAY_KEY_SECRET"] = "test_key_secret"
ENV["RAZORPAY_WEBHOOK_SECRET"] = "test_webhook_secret"
ENV["SELLER_NAME"] = "Saeloun Software Pvt Ltd"
ENV["SELLER_GSTIN"] = "27AAAAA0000A1Z5"
ENV["SELLER_ADDRESS"] = "Pune, Maharashtra"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => error
  abort error.to_s.strip
end

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActiveJob::TestHelper

  config.include Module.new {
    def sign_in_admin(admin = create(:admin_user, password: "password123"))
      post session_path, params: { email: admin.email, password: "password123" }
      admin
    end
  }, type: :request
end
