class Hiring::Application < ApplicationRecord
  MAX_PDF_BYTES = 5.megabytes
  belongs_to :job
  belongs_to :applicant, class_name: "User"
  validates :applicant_id, uniqueness: { scope: :job_id }
  validates :consented_at, presence: true
  validate :profile_and_pdf

  def withdraw!
    update!(withdrawn_at: Time.current, snapshot: {}, quarantined_pdf: nil)
  end

  private
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
