class InitiateRefundJob < ApplicationJob
  class RefundRequest < Razorpay::Request
    def initialize(idempotency_key)
      super("payments")
      @options[:headers]["X-Refund-Idempotency"] = idempotency_key
    end
  end
  private_constant :RefundRequest

  def perform(refund, payment_id)
    LegacyCommerce.assert!(refund)
    return if refund.razorpay_refund_id?

    gateway_refund = RefundRequest.new("dqor-refund-#{refund.id}").post("#{payment_id}/refund", amount: refund.amount_paise)
    # Event insertion references the order; use the same order-first discipline
    # as processing, after the gateway call has completed.
    refund.order.with_lock do
      refund.with_lock do
        return if refund.razorpay_refund_id?

        refund.update!(razorpay_refund_id: gateway_refund.id)
        refund.order.payment_events.create_or_find_by!(razorpay_event_id: "refund_created_#{gateway_refund.id}") do |event|
          event.kind = "refund_created"
          event.amount_paise = refund.amount_paise
          event.raw = { "razorpay_refund_id" => gateway_refund.id }
        end
      end
    end
  rescue Razorpay::Error => error
    raise ApplicationJob::TransientRazorpayError, error.message if [ 409, 429 ].include?(error.status.to_i) || error.status.to_i >= 500

    raise
  end
end
