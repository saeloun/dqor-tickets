require "rails_helper"

RSpec.describe "Multi-gateway schema" do
  it "gives new orders razorpay/INR/IN gateway defaults" do
    order = create(:order)

    expect(order.reload.gateway).to eq("razorpay")
    expect(order.currency).to eq("INR")
    expect(order.country).to eq("IN")
  end

  it "adds the parallel gateway columns to payment_events, refunds and ticket_types" do
    expect(PaymentEvent.column_names).to include("gateway", "gateway_event_id", "gateway_payment_id")
    expect(Refund.column_names).to include("gateway", "gateway_refund_id")
    expect(TicketType.column_names).to include("prices_minor")
  end

  it "enforces a unique index on payment_events [gateway, gateway_event_id]" do
    index_names = ActiveRecord::Base.connection.indexes(:payment_events).map(&:name)

    expect(index_names).to include("index_payment_events_on_gateway_and_gateway_event_id")
  end

  it "creates a payments table backing a Payment model" do
    order = create(:order)

    payment = Payment.create!(order:, gateway: "razorpay", status: "captured", amount_minor: 550_000, currency: "INR")

    expect(payment).to be_captured
    expect(payment.reload.gateway).to eq("razorpay")
  end

  it "leaves the razorpay_* columns intact and authoritative" do
    expect(Order.column_names).to include("razorpay_order_id")
    expect(PaymentEvent.column_names).to include("razorpay_event_id", "razorpay_payment_id")
    expect(Refund.column_names).to include("razorpay_refund_id")
  end
end
