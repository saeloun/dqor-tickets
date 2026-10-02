class Hiring::ScanResumeJob < ApplicationJob
  queue_as :hiring_scans

  def perform(application_id)
    application = Hiring::Application.find(application_id)
    return if application.withdrawn_at? || application.quarantined_pdf.blank?
    bytes = application.quarantined_pdf.dup.freeze
    digest = Digest::SHA256.hexdigest(bytes)
    verdict = Rails.configuration.x.hiring_resume_scanner.scan(bytes)
    application.with_lock do
      return if application.withdrawn_at? || application.quarantined_pdf.blank?
      return unless Digest::SHA256.hexdigest(application.quarantined_pdf) == digest
      clean = verdict.status == "clean" && verdict.digest == digest
      application.update!(scan_status: clean ? "clean" : "quarantined", scan_digest: clean ? digest : nil, scanned_at: clean ? Time.current : nil)
    end
  rescue StandardError
    # Failure must not preserve a previous clean verdict; never log document bytes.
    application&.update_columns(scan_status: "quarantined", scan_digest: nil, scanned_at: nil)
    raise
  end
end
