Rails.application.config.x.hiring_enabled = ENV["HIRING_ENABLED"] == "true"
Rails.application.config.filter_parameters += [ :snapshot, :evidence, :resume ]
Rails.application.config.x.hiring_resume_downloads_enabled = ENV["HIRING_RESUME_DOWNLOADS_ENABLED"] == "true"
# Lazy construction avoids referencing reloadable application classes in an initializer.
Rails.application.config.to_prepare do
  Rails.application.config.x.hiring_resume_scanner = if ENV["HIRING_RESUME_SCANNER"] == "clamav"
    Hiring::ClamavScanner.new(executable: ENV["HIRING_CLAMSCAN_PATH"], database: ENV["HIRING_CLAMAV_DATABASE"])
  else
    Hiring::ResumeScanner.new
  end
end
Rails.application.config.filter_parameters += [ :token, :quarantined_pdf ]
