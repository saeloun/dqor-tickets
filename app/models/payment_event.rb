class PaymentEvent < ApplicationRecord
  belongs_to :order

  validates :razorpay_event_id, :kind, presence: true
  validates :razorpay_event_id, :razorpay_payment_id, uniqueness: true, allow_nil: true
  validates :amount_paise, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
