class PaymentEvent < ApplicationRecord
  belongs_to :order

  before_validation :stamp_mode, on: :create

  validates :razorpay_event_id, :kind, presence: true
  validates :razorpay_event_id, :razorpay_payment_id, uniqueness: true, allow_nil: true
  validates :amount_paise, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :level, inclusion: { in: %w[info warn error] }
  validates :mode, inclusion: { in: %w[test live] }, allow_nil: true

  def self.record_webhook!(order:, event_id:, kind:, amount_paise:, raw:, razorpay_payment_id: nil)
    now = Time.current
    result = transaction(requires_new: true) do
      insert_all!(
        [ {
          order_id: order.id,
          razorpay_event_id: event_id,
          razorpay_payment_id:,
          kind:,
          level: "info",
          mode: gateway_mode,
          amount_paise:,
          raw:,
          created_at: now,
          updated_at: now
        } ],
        returning: %w[id]
      )
    end
    find(result.rows.sole.sole)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def self.gateway_mode
    key = ENV["RAZORPAY_KEY_ID"].to_s
    return "test" if key.start_with?("rzp_test_")
    "live" if key.start_with?("rzp_live_")
  end

  private
    def stamp_mode
      self.mode ||= self.class.gateway_mode
    end
end
