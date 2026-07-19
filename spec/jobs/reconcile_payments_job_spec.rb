require "rails_helper"

RSpec.describe ReconcilePaymentsJob, type: :job do
  it "completes a captured pending payment through the confirmation path" do
    order = create(:order, created_at: 3.minutes.ago, razorpay_order_id: "order_test")
    create(:ticket, order:)
    stub_request(:get, "https://api.razorpay.com/v1/orders/order_test").to_return(
      status: 200,
      body: { entity: "order", id: "order_test" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
    stub_request(:get, "https://api.razorpay.com/v1/orders/order_test/payments").to_return(
      status: 200,
      body: { entity: "collection", items: [ { id: "pay_test", entity: "payment", amount: order.total_paise, captured: true } ] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    expect { described_class.perform_now }.to have_enqueued_job(DeliverOrderConfirmationJob).with(order)

    expect(order.reload).to be_paid
    expect(order.payment_events.sole).to have_attributes(kind: "reconciled_captured", razorpay_payment_id: "pay_test", level: "info", mode: "test")
  end

  it "records a warning when polling fails" do
    order = create(:order, created_at: 3.minutes.ago, razorpay_order_id: "order_failed")
    stub_request(:get, "https://api.razorpay.com/v1/orders/order_failed").to_return(
      status: 500,
      body: { error: { code: "SERVER_ERROR", description: "unavailable" } }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    expect { described_class.perform_now }.to have_enqueued_job(described_class)

    expect(order.payment_events.sole).to have_attributes(kind: "polling_check_failed", level: "warn", mode: "test")
  end

  it "records a successful poll when no payment is captured" do
    order = create(:order, created_at: 3.minutes.ago, razorpay_order_id: "order_pending")
    stub_request(:get, "https://api.razorpay.com/v1/orders/order_pending").to_return(
      status: 200,
      body: { entity: "order", id: "order_pending" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
    stub_request(:get, "https://api.razorpay.com/v1/orders/order_pending/payments").to_return(
      status: 200,
      body: { entity: "collection", items: [] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.perform_now

    expect(order.reload).to be_pending
    expect(order.payment_events.sole).to have_attributes(kind: "polling_checked", level: "info", mode: "test")
  end
end
