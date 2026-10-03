class EventSlot < ApplicationRecord
  has_many :redemptions, class_name: "EventSlotRedemption", dependent: :restrict_with_exception
  validates :name, presence: true, length: { maximum: 120 }
  validates :starts_at, :ends_at, presence: true
  validates :redemption_limit, numericality: { only_integer: true, greater_than: 0 }
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :valid_configuration

  private
    def valid_configuration
      errors.add(:ends_at, "must follow start") if starts_at && ends_at && ends_at <= starts_at
      errors.add(:ticket_type_ids, "must explicitly select eligible ticket types") if active? && ticket_type_ids.empty?
      errors.add(:ticket_type_ids, "contains unknown types") unless (ticket_type_ids - TicketType.where(id: ticket_type_ids).pluck(:id)).empty?
    end
end
