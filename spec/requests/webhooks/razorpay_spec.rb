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
      .not_to change(PaymentEvent, :count)

    expect(response).to have_http_status(:bad_request)
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
end
