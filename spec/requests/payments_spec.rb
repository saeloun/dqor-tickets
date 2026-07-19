require "rails_helper"

RSpec.describe "Payments", type: :request do
  let(:order) { create(:order, razorpay_order_id: "order_test") }
  let(:payment_id) { "pay_test" }

  def signature
    OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("RAZORPAY_KEY_SECRET"), "#{order.razorpay_order_id}|#{payment_id}")
  end

  it "records a verified callback without marking the order paid" do
    post payment_callback_path, params: {
      razorpay_order_id: order.razorpay_order_id,
      razorpay_payment_id: payment_id,
      razorpay_signature: signature
    }

    expect(response).to redirect_to(order_path(order.code))
    expect(order.reload).to be_pending
    expect(order.payment_events.sole).to have_attributes(kind: "callback_verified", razorpay_payment_id: payment_id)
  end

  it "rejects an invalid signature" do
    expect do
      post payment_callback_path, params: {
        razorpay_order_id: order.razorpay_order_id,
        razorpay_payment_id: payment_id,
        razorpay_signature: "invalid"
      }
    end.not_to change(PaymentEvent, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end
end
