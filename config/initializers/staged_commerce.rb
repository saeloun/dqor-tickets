# Internal service staging only. This does not enable multitenant commerce.
Rails.application.config.x.staged_commerce_enabled = ENV["STAGED_COMMERCE_ENABLED"] == "true"
