Rails.application.config.x.hiring_enabled = ENV["HIRING_ENABLED"] == "true"
Rails.application.config.filter_parameters += [ :snapshot, :evidence, :resume ]
