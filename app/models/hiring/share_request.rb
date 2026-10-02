class Hiring::ShareRequest < ApplicationRecord
  belongs_to :job
  belongs_to :recipient, class_name: "User"
  belongs_to :applicant, class_name: "User", optional: true
  has_one :application, class_name: "Hiring::Application"
  validates :token_digest, :expires_at, presence: true

  def available?
    !consented_at? && !revoked_at? && expires_at.future? && recipient_authorized?
  end

  def recipient_authorized?
    job.recruiter_id == recipient_id && job.company.claimant_id == recipient_id && job.company.status == "approved"
  end

  def active?
    consented_at? && !revoked_at? && expires_at.future? && recipient_authorized?
  end
end
