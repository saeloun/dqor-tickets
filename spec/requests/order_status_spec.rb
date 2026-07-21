require "rails_helper"

RSpec.describe "Order status", type: :request do
  it "shows a polling confirmation state for a pending order" do
    order = create(:order)

    get order_path(order.code)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Confirming your payment", "data-controller=\"poll\"")
  end

  it "shows a paid order with invoice download and attendee assignment" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:, attendee_name: nil, attendee_email: nil)
    invoice = Invoice.issue_for!(order)
    invoice.pdf.attach(io: StringIO.new("invoice"), filename: "invoice.pdf", content_type: "application/pdf")

    get order_path(order.code)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your tickets are confirmed", "Download tax invoice", "0 of 1 tickets assigned", "Assign this ticket")
    expect(response.body).to include(ticket_claim_url(ticket.claim_token))
    expect(response.body).not_to include("Download ticket")
  end

  it "regenerates a missing invoice without generating an unassigned ticket" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:, attendee_name: nil, attendee_email: nil)
    invoice = Invoice.issue_for!(order)
    allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")

    get order_path(order.code)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Download tax invoice", "Assign this ticket")
    expect(invoice.reload.pdf).to be_attached
    expect(ticket.reload.pdf).not_to be_attached
  end

  it "shows an expired order with a retry link" do
    order = create(:order, status: :expired, expires_at: 1.minute.ago)

    get order_path(order.code)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("This order expired", "Try again")
  end

  it "fetches Razorpay once after a verified callback stalls" do
    order = create(:order, razorpay_order_id: "order_test")
    create(:payment_event, order:, kind: "callback_verified", razorpay_payment_id: "pay_callback", created_at: 31.seconds.ago)
    stub_request(:get, "https://api.razorpay.com/v1/orders/order_test").to_return(
      status: 200,
      body: { entity: "order", id: "order_test", status: "paid" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
    stub_request(:get, "https://api.razorpay.com/v1/orders/order_test/payments").to_return(
      status: 200,
      body: { entity: "collection", items: [ { id: "pay_test", amount: order.total_paise, captured: true } ] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    expect { get order_path(order.code) }
      .to have_enqueued_job(ConfirmOrderJob).with(order.razorpay_order_id, kind_of(Integer))

    get order_path(order.code)

    expect(a_request(:get, "https://api.razorpay.com/v1/orders/order_test")).to have_been_made.once
    expect(order.reload.metadata).to include("fallback_checked_at")
  end
end
