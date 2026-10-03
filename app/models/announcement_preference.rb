class AnnouncementPreference < ApplicationRecord
  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  scope :consented, -> { where.not(consented_at: nil).where(suppressed_at: nil) }

  def self.eligible?(email)
    consented.exists?(email: email) && Ticket.confirmed.where("lower(btrim(attendee_email)) = ?", email).exists?
  end
end
