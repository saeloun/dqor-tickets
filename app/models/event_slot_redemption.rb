class EventSlotRedemption < ApplicationRecord
  belongs_to :event_slot
  belongs_to :ticket
  belongs_to :admin_user
  belongs_to :voided_by, class_name: "AdminUser", optional: true
  scope :current, -> { where(voided_at: nil) }
  validates :request_key, presence: true, length: { maximum: 100 }
end
