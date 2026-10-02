Rails.application.config.x.hiring_enabled = ENV["HIRING_ENABLED"] == "true"
Rails.application.config.filter_parameters += [ :snapshot, :evidence, :resume ]
Rails.application.config.x.hiring_resume_downloads_enabled = ENV["HIRING_RESUME_DOWNLOADS_ENABLED"] == "true"
# Lazy construction avoids referencing reloadable application classes in an initializer.
Rails.application.config.to_prepare do
  Rails.application.config.x.hiring_resume_scanner = Hiring::ResumeScanner.new
end
Rails.application.config.filter_parameters += [ :token, :quarantined_pdf ]
