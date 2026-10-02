# Enable only after explicit organization and membership provisioning is reviewed.
Rails.application.config.x.organizer_platform_enabled = ENV["ORGANIZER_PLATFORM_ENABLED"] == "true"
