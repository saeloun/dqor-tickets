class WaitlistEntry < ApplicationRecord
  belongs_to :event
  belongs_to :ticket_type, optional: true
  belongs_to :user, optional: true
  belongs_to :order, optional: true

  has_secure_token :offer_token
  has_secure_token :cancel_token

  enum :status, {
    waiting: "waiting",
    offered: "offered",
    purchased: "purchased",
    expired: "expired",
    cancelled: "cancelled"
  }, validate: true

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: [ :event_id, :ticket_type_id ] }

  scope :waiting_in_order, -> { where(status: "waiting").order(:position, :id) }

  def offer!(expires_in: 24.hours)
    update!(status: "offered", offered_at: Time.current, offer_expires_at: expires_in.from_now)
  end

  def offer_expired?
    offered? && offer_expires_at.present? && offer_expires_at < Time.current
  end
end
