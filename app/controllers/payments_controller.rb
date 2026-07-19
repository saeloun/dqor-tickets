class PaymentsController < ApplicationController
  allow_unauthenticated_access

  def callback
    razorpay_order_id, razorpay_payment_id, razorpay_signature = params.expect(
      :razorpay_order_id,
      :razorpay_payment_id,
      :razorpay_signature
    )
    Razorpay::Utility.verify_payment_signature(razorpay_order_id:, razorpay_payment_id:, razorpay_signature:)

    order = Order.find_by!(razorpay_order_id:)
    order.payment_events.create_or_find_by!(razorpay_event_id: "callback_#{razorpay_payment_id}") do |event|
      event.razorpay_payment_id = razorpay_payment_id
      event.kind = "callback_verified"
      event.amount_paise = order.total_paise
    end
    redirect_to order_path(order.code)
  rescue SecurityError
    head :unprocessable_content
  end
end
