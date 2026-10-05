class Hiring::Application < ApplicationRecord
  belongs_to :share_request, optional: true
  before_save :reset_scan, if: :will_save_change_to_quarantined_pdf?
  after_create_commit :queue_scan
  MAX_PDF_BYTES = 5.megabytes
  belongs_to :job
  belongs_to :applicant, class_name: "User"
  validates :applicant_id, uniqueness: { scope: :job_id }
  validates :consented_at, presence: true
  validate :profile_and_pdf

  def withdraw!
    update!(withdrawn_at: Time.current, snapshot: {}, quarantined_pdf: nil)
  end

  def consent_active?
    !withdrawn_at? && (share_request.nil? || share_request.active?)
  end

  def resume_releasable?
    Rails.configuration.x.hiring_resume_downloads_enabled && consent_active? &&
      quarantined_pdf.present? && scan_status == "clean" && scanned_at.present? &&
      resume_digest == scan_digest && scan_digest == Digest::SHA256.hexdigest(quarantined_pdf)
  end

  private
    def reset_scan
      self.resume_digest = quarantined_pdf.present? ? Digest::SHA256.hexdigest(quarantined_pdf) : nil
      self.scan_digest = nil
      self.scan_status = "quarantined"
      self.scanned_at = nil
    end

    def queue_scan
      Hiring::ScanResumeJob.perform_later(id) if quarantined_pdf.present?
    end

    def profile_and_pdf
      return if withdrawn_at?
      errors.add(:snapshot, "requires a name and summary") if snapshot["name"].blank? || snapshot["summary"].blank?
      errors.add(:snapshot, "is too long") if snapshot.to_json.bytesize > 15000
      linkedin = snapshot["linkedin"].to_s
      errors.add(:snapshot, "LinkedIn must be a profile URL") unless linkedin.blank? || linkedin.match?(%r{\Ahttps://(?:www\.)?linkedin\.com/in/[A-Za-z0-9_%\-]+/?\z})
      if quarantined_pdf && (quarantined_pdf.bytesize > MAX_PDF_BYTES || !quarantined_pdf.start_with?("%PDF-"))
        errors.add(:base, "Resume must be a PDF of at most 5 MB")
      end
    end
end
