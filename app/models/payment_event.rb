class PaymentEvent < ApplicationRecord
  belongs_to :order

  validates :razorpay_event_id, :kind, presence: true
  validates :razorpay_event_id, :razorpay_payment_id, uniqueness: true, allow_nil: true
  validates :amount_paise, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.record_webhook!(order:, event_id:, kind:, amount_paise:, raw:)
    now = Time.current
    result = transaction(requires_new: true) do
      insert_all!(
        [ { order_id: order.id, razorpay_event_id: event_id, kind:, amount_paise:, raw:, created_at: now, updated_at: now } ],
        returning: %w[id]
      )
    end
    find(result.rows.sole.sole)
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
