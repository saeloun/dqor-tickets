RSpec.configure do |config|
  config.before { Rails.cache.clear }
end
