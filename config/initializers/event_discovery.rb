Rails.configuration.x.event_discovery_enabled = ENV["EVENT_DISCOVERY_ENABLED"] == "true"
Rails.configuration.x.discovery_product_name = ENV.fetch("DISCOVERY_PRODUCT_NAME", "DQOR Discover")
