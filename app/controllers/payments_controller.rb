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
    if order = Order.find_by(razorpay_order_id: params[:razorpay_order_id])
      order.payment_events.create!(
        razorpay_event_id: "signature_mismatch_#{SecureRandom.uuid}",
        kind: "signature_mismatch",
        level: "warn",
        amount_paise: order.total_paise,
        raw: params.permit(:razorpay_order_id, :razorpay_payment_id).to_h
      )
    end
    head :unprocessable_content
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "We couldn't confirm that payment automatically. If you were charged, your tickets will arrive by email shortly — contact us if they don't."
  end
end
