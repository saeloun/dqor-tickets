Rails.configuration.x.free_event_questions_enabled = ENV["FREE_EVENT_QUESTIONS_ENABLED"] == "true"
Rails.application.config.filter_parameters += [ :registration_answers, :answers ]
