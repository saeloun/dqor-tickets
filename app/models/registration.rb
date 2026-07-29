class Registration < ApplicationRecord
  belongs_to :event
  belongs_to :user
  belongs_to :ticket, optional: true

  after_create_commit -> { broadcast_replace_to(event, target: "guest_list", partial: "registrations/guest_list", locals: { event: event }) }, if: -> { event.guest_list_public? }

  enum :attendance_state, {
    interested: "interested",
    going: "going",
    waitlisted: "waitlisted",
    pending_approval: "pending_approval",
    cancelled: "cancelled"
  }, validate: true

  enum :payment_state, {
    not_required: "not_required",
    awaiting_payment: "awaiting_payment",
    authorized: "authorized",
    captured: "captured",
    refunded: "refunded",
    released: "released"
  }, validate: true

  validates :source, presence: true
  validates :user_id, uniqueness: { scope: :event_id }

  scope :public_guests, -> {
    where(attendance_state: %w[interested going]).where.not(payment_state: %w[refunded released])
  }

  def attending?
    going? && (not_required? || captured?)
  end
end
