class Coupon < ApplicationRecord
  class Invalid < StandardError; end

  def self.find_by_code(code)
    code = code.to_s.strip
    return if code.blank?

    find_by("lower(code) = ?", code.downcase) || raise(Invalid, "Coupon not valid")
  end

  belongs_to :ticket_type, optional: true
  has_many :orders, dependent: :restrict_with_exception

  normalizes :code, with: ->(code) { code.strip.upcase }

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :discount_paise, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :percent, numericality: { only_integer: true, in: 1..100 }, allow_nil: true
  validates :max_uses, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :uses_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :one_discount_type
  validate :valid_window_is_ordered

  def discount_for(subtotals, at: Time.current)
    message = unavailable_message(at:)
    raise Invalid, message if message

    subtotal = ticket_type_id ? subtotals.fetch(ticket_type_id, 0) : subtotals.values.sum
    raise Invalid, "Coupon does not apply to these tickets" if subtotal.zero?

    [ discount_paise || (subtotal * percent / 100.0).round, subtotal ].min
  end

  def available?(at: Time.current)
    active? && (!valid_from || valid_from <= at) && (!valid_until || valid_until >= at) && (!max_uses || uses_count < max_uses)
  end

  private
    def unavailable_message(at:)
      return "Coupon not active" unless active?
      return "Coupon not valid yet" if valid_from && valid_from > at
      return "Coupon has expired" if valid_until && valid_until < at
      "Coupon usage limit reached" if max_uses && uses_count >= max_uses
    end

    def one_discount_type
      errors.add(:base, "set either discount paise or percent") unless discount_paise.present? ^ percent.present?
    end

    def valid_window_is_ordered
      errors.add(:valid_until, "must be after valid from") if valid_from && valid_until && valid_until < valid_from
    end
end
