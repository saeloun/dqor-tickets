class TicketType < ApplicationRecord
  has_many :tickets, dependent: :restrict_with_exception
  has_many :coupons, dependent: :nullify

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
  validates :price_paise, :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :min_per_order, numericality: { only_integer: true, greater_than: 0 }
  validates :capacity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :max_per_order, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :sales_window_is_ordered
  validate :order_limits_are_ordered

  def available_quantity(at: Time.current)
    return Float::INFINITY unless capacity

    capacity - tickets.where(canceled_at: nil).joins(:order).merge(Order.reserving_inventory(at)).count
  end

  def purchasable?(at: Time.current)
    active? && (!sales_start_at || sales_start_at <= at) && (!sales_end_at || sales_end_at >= at)
  end

  def conference_pass?
    slug.start_with?("conference-pass-")
  end

  private
    def sales_window_is_ordered
      errors.add(:sales_end_at, "must be after sales start") if sales_start_at && sales_end_at && sales_end_at < sales_start_at
    end

    def order_limits_are_ordered
      errors.add(:max_per_order, "must be at least the minimum") if max_per_order && max_per_order < min_per_order
    end
end
