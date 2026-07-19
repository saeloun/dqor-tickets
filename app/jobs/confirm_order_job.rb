class ConfirmOrderJob < ApplicationJob
  def perform(razorpay_order_id, payment_event_id)
    order = Order.find_by!(razorpay_order_id:)
    payment_event = order.payment_events.find(payment_event_id)

    order.mark_paid!(payment_event)
    DeliverOrderConfirmationJob.perform_later(order)
  rescue Order::InsufficientAvailability
    order.update!(status: :expired, metadata: order.metadata.merge("late_payment_requires_refund" => true))
  end
end
