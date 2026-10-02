require "rails_helper"

RSpec.describe "Pending accounting documents", type: :model do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-synthetic") }

  def without_policy
    previous = ENV["INVOICE_POLICY_VERSION"]
    ENV.delete("INVOICE_POLICY_VERSION")
    yield
  ensure
    ENV["INVOICE_POLICY_VERSION"] = previous
  end

  def purchase(**attributes)
    order = create(:order, **attributes)
    ticket = create(:ticket, order:)
    event = create(:payment_event, order:, amount_paise: order.total_paise)
    [ order, ticket, event ]
  end

  it "keeps captured payments paid, tickets valid and coupon use singular while invoice configuration is missing" do
    coupon = create(:coupon, uses_count: 0)
    order, ticket, event = purchase(coupon:)
    without_policy do
      expect(order.mark_paid!(event)).to be(true)
      expect(order.mark_paid!(event)).to be(false)
      expect(order.reload).to be_paid
      expect(ticket.reload.canceled_at).to be_nil
      expect(coupon.reload.uses_count).to eq(1)
      expect(order.invoices).to be_empty
      expect(order.metadata["invoice_pending_reason"]).to eq("InvoicePolicy::NotConfigured")
      expect(order.metadata["invoice_purchase_lines"].sole["total_paise"]).to eq(event.amount_paise)
    end
  end

  it "sends honest pending confirmation then retries once into the original captured purchase amounts" do
    order, ticket, event = purchase
    without_policy do
      order.mark_paid!(event)
      DeliverOrderConfirmationJob.perform_now(order)
      expect(order.reload.metadata["confirmation_documents_pending"]).to be(true)
      expect(enqueued_jobs.map { |job| job[:job] }).to include(GenerateOrderDocumentsJob)
      expect(OrderMailer.confirmation(order, documents_pending: true).attachments).to be_empty
      expect(order.invoices).to be_empty
    end
    ticket.update!(price_paise: 1)
    2.times { GenerateOrderDocumentsJob.perform_now(order.reload) }
    invoice = order.invoices.invoice.sole
    expect(invoice.line_items.sole["total_paise"]).to eq(event.amount_paise)
    expect(invoice.pdf).to be_attached
    expect(order.reload.metadata["confirmation_documents_pending"]).to be(false)
    expect(order.metadata).not_to have_key("invoice_pending_reason")
    expect(enqueued_jobs.count { |job| job[:job] == MailDeliveryJob }).to eq(2)
  end

  it "keeps payment confirmed when a registered buyer address needs remediation" do
    order, ticket, event = purchase(gstin: "29AAAAA0000A1Z5", billing_state_code: "29")
    order.mark_paid!(event)
    expect(order.reload).to be_paid
    expect(ticket.reload.canceled_at).to be_nil
    expect(order.invoices).to be_empty
    expect(order.metadata["invoice_pending_reason"]).to eq("ActiveRecord::RecordInvalid")
    order.update!(metadata: order.metadata.merge("billing_address" => "Verified test address", "billing_state_name" => "Karnataka"))
    order.attach_documents!
    expect(order.invoices.invoice.sole.pdf).to be_attached
  end

  it "processes legitimate legacy refunds while keeping credit-document remediation separate" do
    order, ticket, event = purchase
    order.update!(status: :paid)
    Invoice.insert_all!([ {
      order_id: order.id, number: "DQOR/2026-27/0001", issued_on: Date.new(2026, 7, 19), kind: "invoice",
      buyer_snapshot: Invoice.buyer_snapshot(order), line_items: Invoice.line_item_snapshot(order),
      created_at: Time.current, updated_at: Time.current
    } ])
    refund = create(:refund, order:, status: :initiated, ticket_ids: [ ticket.id ], amount_paise: ticket.price_paise)
    processed_event = create(:payment_event, order:, kind: "refund.processed", amount_paise: refund.amount_paise)
    2.times { expect(refund.process!(processed_event)).to be_nil }
    expect(refund.reload).to be_processed
    expect(refund).to be_credit_note_pending
    expect(ticket.reload.canceled_at).to be_present
    expect(order.invoices.credit_note).to be_empty
    expect(order.reload.metadata["credit_notes_pending"]).to include(refund.id.to_s => "Invoice::LegacySnapshotUnavailable")
    expect { ProcessRefundJob.new.perform(refund.id, processed_event.id) }.to raise_error(Invoice::DocumentPending)
    expect(enqueued_jobs.select { |job| job[:job] == MailDeliveryJob }).to be_empty
  end

  it "allows refunds using captured lines when policy blocked the original invoice and later creates one credit" do
    order, ticket, event = purchase
    event.update!(razorpay_payment_id: "pay_synthetic")
    refund = nil
    processed_event = nil
    without_policy do
      order.mark_paid!(event)
      # This schedules the existing idempotent gateway refund; no gateway call is made here.
      refund = order.refund_tickets!([ ticket.id ])
      expect(refund.amount_paise).to eq(event.amount_paise)
      processed_event = create(:payment_event, order:, kind: "refund.processed", amount_paise: refund.amount_paise)
      expect(refund.process!(processed_event)).to be_nil
      expect(refund.reload).to be_processed
      expect(refund).to be_credit_note_pending
      expect(ticket.reload.canceled_at).to be_present
    end
    order.reload.attach_documents!
    first = refund.process!(processed_event)
    second = refund.process!(processed_event)
    expect(second).to eq(first)
    expect(order.invoices.credit_note.count).to eq(1)
    expect(refund.reload).not_to be_credit_note_pending
    expect(order.reload.metadata["credit_notes_pending"]).not_to have_key(refund.id.to_s)
    expect(first.line_items.sum { |line| line["total_paise"] }).to eq(refund.amount_paise)
  end
end
