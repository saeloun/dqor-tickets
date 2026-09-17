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

  it "marks a refund failed when Razorpay permanently rejects it" do
    refund = create(:refund, status: "initiated")
    stub_request(:post, "https://api.razorpay.com/v1/payments/pay_test/refund")
      .to_return(
        status: 400,
        body: { error: { code: "BAD_REQUEST_ERROR", description: "invalid refund" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    expect { described_class.perform_now(refund, "pay_test") }.to raise_error(Razorpay::Error)

    expect(refund.reload).to be_failed
  end
end
