require "rails_helper"

RSpec.describe "Razorpay webhooks", type: :request do
  def post_webhook(payload, event_id: "event_test", signature: nil)
    body = payload.to_json
    signature ||= OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("RAZORPAY_WEBHOOK_SECRET"), body)
    post webhooks_razorpay_path,
      params: body,
      headers: {
        "Content-Type" => "application/json",
        "X-Razorpay-Event-Id" => event_id,
        "X-Razorpay-Signature" => signature
      }
  end

  def payment_payload(event, order)
    {
      event:,
      payload: {
        payment: {
          entity: {
            id: "pay_test",
            order_id: order.razorpay_order_id,
            amount: order.total_paise,
            captured: event == "payment.captured"
          }
        }
      }
    }
  end

  it "enqueues confirmation for a valid signed payment event" do
    order = create(:order, razorpay_order_id: "order_test")

    expect { post_webhook(payment_payload("payment.captured", order)) }
      .to have_enqueued_job(ConfirmOrderJob).with(order.razorpay_order_id, kind_of(Integer))

    expect(response).to have_http_status(:ok)
    expect(order.payment_events.sole.kind).to eq("payment.captured")
  end

  it "rejects an invalid signature" do
    order = create(:order, razorpay_order_id: "order_test")

    expect { post_webhook(payment_payload("payment.captured", order), signature: "invalid") }
      .to change(PaymentEvent, :count).by(1)

    expect(response).to have_http_status(:bad_request)
    expect(order.payment_events.sole).to have_attributes(kind: "signature_mismatch", level: "warn", mode: "test")
  end

  it "raises when the webhook secret is missing" do
    order = create(:order, razorpay_order_id: "order_test")
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("RAZORPAY_WEBHOOK_SECRET").and_raise(KeyError, "key not found")

    expect { post_webhook(payment_payload("payment.captured", order), signature: "signed") }
      .to raise_error(KeyError, "key not found")
  end

  it "deduplicates an event before processing" do
    order = create(:order, razorpay_order_id: "order_test")
    payload = payment_payload("order.paid", order)

    clear_enqueued_jobs
    expect { 2.times { post_webhook(payload) } }.to change(PaymentEvent, :count).by(1)

    jobs = enqueued_jobs.select { |job| job[:job] == ConfirmOrderJob }
    expect(jobs.size).to eq(1)
    expect(response).to have_http_status(:ok)
  end

  it "records a failed payment without confirming the order" do
    order = create(:order, razorpay_order_id: "order_test")

    clear_enqueued_jobs
    expect { post_webhook(payment_payload("payment.failed", order)) }
      .to change(PaymentEvent, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(order.payment_events.sole.kind).to eq("payment.failed")
    expect(enqueued_jobs).to be_empty
  end

  it "enqueues refund processing" do
    order = create(:order, :paid, razorpay_order_id: "order_test")
    ticket = create(:ticket, order:)
    Invoice.issue_for!(order)
    refund = create(:refund, order:, razorpay_refund_id: "rfnd_test", ticket_ids: [ ticket.id ])
    payload = {
      event: "refund.processed",
      payload: { refund: { entity: { id: refund.razorpay_refund_id, amount: refund.amount_paise } } }
    }

    expect { post_webhook(payload) }
      .to have_enqueued_job(ProcessRefundJob).with(refund.id, kind_of(Integer))

    expect(response).to have_http_status(:ok)
  end
  it "releases a failed refund once and ignores a stale failure after processing" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:)
    Invoice.issue_for!(order)
    refund = create(:refund, order:, razorpay_refund_id: "rfnd_failed", status: "initiated", ticket_ids: [ ticket.id ])
    payload = { event: "refund.failed", payload: { refund: { entity: { id: refund.razorpay_refund_id, amount: refund.amount_paise } } } }
    2.times { post_webhook(payload) }
    expect(response).to have_http_status(:ok)
    expect(refund.reload).to be_failed
    expect(order.payment_events.where(kind: "refund_failed").count).to eq(1)
    expect(ticket.reload.canceled_at).to be_nil
    expect(enqueued_jobs).to be_empty

    refund.update!(status: "processed")
    post_webhook(payload, event_id: "stale_failure")
    expect(refund.reload).to be_processed
  end

  it "does not release reservations for a mismatched failed webhook amount" do
    refund = create(:refund, status: "initiated", razorpay_refund_id: "rfnd_failed")
    payload = { event: "refund.failed", payload: { refund: { entity: { id: refund.razorpay_refund_id, amount: refund.amount_paise + 1 } } } }
    post_webhook(payload)
    expect(refund.reload).to be_initiated
  end

  it "rolls back a processed webhook event when durable enqueue fails so delivery can retry" do
    order = create(:order, :paid)
    refund = create(:refund, order:, razorpay_refund_id: "rfnd_queue")
    payload = { event: "refund.processed", payload: { refund: { entity: { id: refund.razorpay_refund_id, amount: refund.amount_paise } } } }
    allow(ProcessRefundJob).to receive(:perform_later).and_return(false)
    expect { post_webhook(payload) }.to raise_error(ActiveJob::EnqueueError)
    expect(order.payment_events.where(razorpay_event_id: "event_test")).to be_empty
  end
  it "preserves provider processing evidence when a stale failure arrives before the worker" do
    allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")
    order = create(:order, :paid)
    ticket = create(:ticket, order:)
    Invoice.issue_for!(order)
    refund = create(:refund, order:, razorpay_refund_id: "rfnd_monotonic", status: "initiated", ticket_ids: [ ticket.id ], amount_paise: ticket.price_paise)
    entity = { id: refund.razorpay_refund_id, amount: refund.amount_paise }
    post_webhook({ event: "refund.processed", payload: { refund: { entity: } } }, event_id: "processed_first")
    post_webhook({ event: "refund.failed", payload: { refund: { entity: } } }, event_id: "stale_failed_second")
    expect(refund.reload).to be_initiated
    event = order.payment_events.find_by!(razorpay_event_id: "processed_first")
    ProcessRefundJob.perform_now(refund.id, event.id)
    expect(refund.reload).to be_processed
    expect(ticket.reload.canceled_at).to be_present
    expect(order.payment_events.where(kind: "refund_failed")).to be_empty
  end
end
