require "rails_helper"

RSpec.describe InitiateRefundJob, type: :job do
  it "retries an ambiguous timeout with the same idempotency key" do
    order = create(:order, :paid)
    refund = create(:refund, order:, amount_paise: 100_000, ticket_ids: [ create(:ticket, order:).id ], status: "initiated")
    request = stub_request(:post, "https://api.razorpay.com/v1/payments/pay_test/refund")
      .with(headers: { "X-Refund-Idempotency" => "dqor-refund-#{refund.id}" })
      .to_timeout.then.to_return(
        status: 200,
        body: { entity: "refund", id: "rfnd_test", amount: refund.amount_paise }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    perform_enqueued_jobs do
      described_class.perform_later(refund, "pay_test")
    end

    expect(request).to have_been_requested.twice
    expect(refund.reload).to have_attributes(razorpay_refund_id: "rfnd_test")
    expect(order.payment_events.where(kind: "refund_created").count).to eq(1)
  end
  it "releases a rejected adjustment so cancellation can refund the captured balance" do
    order = create(:order, :paid, total_paise: 550_000)
    type = create(:ticket_type, price_paise: 450_000)
    ticket = create(:ticket, order:, ticket_type: type, price_paise: 550_000)
    Invoice.issue_for!(order)
    create(:payment_event, order:, razorpay_payment_id: "pay_test")
    refund = order.apply_price_adjustment_refund!([ ticket.id ])
    stub_request(:post, "https://api.razorpay.com/v1/payments/pay_test/refund").to_return(
      status: 400, body: { error: { code: "BAD_REQUEST_ERROR", description: "rejected" } }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    expect { described_class.perform_now(refund, "pay_test") }.to raise_error(Razorpay::BadRequestError)
    expect(refund.reload).to be_failed
    expect(order.refund_tickets!([ ticket.id ]).amount_paise).to eq(550_000)
    expect(order.payment_events.find_by!(kind: "refund_failed").raw).to include("refund_id" => refund.id)
    expect { described_class.perform_now(refund, "pay_test") }.not_to raise_error
  end

  it "retains an ambiguous reservation if a later retry receives a rejection" do
    order = create(:order, :paid)
    refund = create(:refund, order:, amount_paise: 100_000, ticket_ids: [ create(:ticket, order:).id ], status: "initiated")
    create(:payment_event, order:, razorpay_event_id: "refund_request_started_#{refund.id}", kind: "refund_request_started", amount_paise: refund.amount_paise)
    stub_request(:post, "https://api.razorpay.com/v1/payments/pay_test/refund").to_return(
      status: 400, body: { error: { code: "BAD_REQUEST_ERROR", description: "rejected after ambiguous prior request" } }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
    expect { described_class.perform_now(refund, "pay_test") }.to raise_error(Razorpay::BadRequestError)
    expect(refund.reload).to be_initiated
  end
end
