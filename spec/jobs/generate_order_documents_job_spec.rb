require "rails_helper"

# This job is the only thing that repairs a confirmation that went out without the
# GST tax invoice attached, so every example here is about it actually closing that loop.
RSpec.describe GenerateOrderDocumentsJob, type: :job do
  before do
    allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")
    ActionMailer::Base.deliveries.clear
  end

  def paid_order
    create(:order, :paid).tap { |order| create(:ticket, order:) }
  end

  it "sends the invoice after a confirmation that went out with documents pending" do
    order = paid_order
    allow(PdfRenderer).to receive(:render).and_raise(Ferrum::DeadBrowserError)

    perform_enqueued_jobs(only: MailDeliveryJob) do
      DeliverOrderConfirmationJob.perform_now(order)
    end

    expect(ActionMailer::Base.deliveries.count).to eq(1)
    expect(ActionMailer::Base.deliveries.last.attachments).to be_empty
    expect(order.reload.metadata).to include("confirmation_documents_pending" => true)
    expect(described_class).to have_been_enqueued.with(order)

    allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")

    perform_enqueued_jobs(only: MailDeliveryJob) do
      perform_enqueued_jobs(only: described_class)
    end

    # The regression: the buyer used to be left with the "being prepared" email forever.
    expect(ActionMailer::Base.deliveries.count).to eq(2)
    invoice = order.invoices.invoice.sole
    expect(invoice.pdf).to be_attached
    expect(ActionMailer::Base.deliveries.last.attachments.map(&:filename))
      .to contain_exactly(invoice.pdf.filename.to_s)
    expect(ActionMailer::Base.deliveries.last.body.encoded).to include("is attached")
    expect(order.reload.metadata).to include("confirmation_documents_pending" => false)
  end

  it "issues the invoice for a paid order that never got one" do
    order = paid_order
    expect(order.invoices).to be_empty

    expect { described_class.perform_now(order) }
      .to change { order.invoices.invoice.count }.from(0).to(1)
      .and have_enqueued_mail(OrderMailer, :confirmation).once

    expect(order.invoices.invoice.sole.pdf).to be_attached
    expect(order.reload.metadata).to include("confirmation_documents_pending" => false)
  end

  it "attaches the PDF to an invoice row that was left without one" do
    order = paid_order
    invoice = Invoice.issue_for!(order)

    perform_enqueued_jobs(only: MailDeliveryJob) { described_class.perform_now(order) }

    expect(invoice.reload.pdf).to be_attached
    expect(order.invoices.invoice.count).to eq(1)
    expect(ActionMailer::Base.deliveries.last.attachments.map(&:filename))
      .to contain_exactly(invoice.pdf.filename.to_s)
  end

  it "does not email a second confirmation once a complete one has gone out" do
    order = paid_order
    order.deliver_confirmation!
    expect(order.reload.metadata).to include("confirmation_documents_pending" => false)

    expect { 2.times { described_class.perform_now(order) } }
      .not_to have_enqueued_mail(OrderMailer, :confirmation)

    expect(order.invoices.invoice.count).to eq(1)
    expect(PdfRenderer).to have_received(:render).once
  end

  it "leaves an unpaid order without an invoice" do
    order = create(:order, status: :pending)
    create(:ticket, order:)

    described_class.perform_now(order)

    expect(order.invoices).to be_empty
    expect(PdfRenderer).not_to have_received(:render)
  end

  it "leaves a policy prerequisite actionable without automatic retries and permits an explicit retry" do
    order = paid_order
    order.deliver_confirmation!(documents_pending: true)
    allow(InvoicePolicy).to receive(:snapshot).and_raise(InvoicePolicy::NotConfigured)
    allow(Rails.logger).to receive(:warn)

    expect do
      perform_enqueued_jobs(only: described_class) { described_class.perform_later(order) }
    end.not_to raise_error

    expect(InvoicePolicy).to have_received(:snapshot).once
    expect(Rails.logger).to have_received(:warn).with("Invoice document requires finance review order_id=#{order.id} reason=InvoicePolicy::NotConfigured").once
    captured = order.reload.metadata.fetch("invoice_purchase_lines")
    expect(order.metadata).to include("invoice_pending_reason" => "InvoicePolicy::NotConfigured", "confirmation_documents_pending" => true)
    expect(order.invoices).to be_empty
    expect(enqueued_jobs.count { |job| job[:job] == described_class }).to eq(0)
    expect(enqueued_jobs.count { |job| job[:job] == MailDeliveryJob }).to eq(1)

    order.tickets.sole.update!(price_paise: 1)
    allow(InvoicePolicy).to receive(:snapshot).and_call_original
    2.times { described_class.perform_now(order.reload) }

    expect(order.invoices.invoice.sole.pdf).to be_attached
    expect(order.invoices.invoice.sole.line_items.sole.fetch("total_paise")).to eq(captured.sole.fetch("total_paise"))
    expect(order.reload.metadata.fetch("invoice_purchase_lines")).to eq(captured)
    expect(order.metadata).not_to have_key("invoice_pending_reason")
    expect(enqueued_jobs.count { |job| job[:job] == MailDeliveryJob }).to eq(2)
  end

  it "does not hide a document error with an unrelated cause or stale pending reason" do
    order = paid_order
    order.update!(metadata: { "invoice_pending_reason" => "InvoicePolicy::NotConfigured" })
    allow(order).to receive(:attach_documents!).and_raise(Invoice::DocumentPending)
    expect { described_class.new.perform(order) }.to raise_error(Invoice::DocumentPending)

    order.update!(metadata: { "invoice_pending_reason" => "Invoice::LegacySnapshotUnavailable" })
    allow(order).to receive(:attach_documents!) do
      raise Invoice::DocumentPending, "synthetic prerequisite", cause: InvoicePolicy::NotConfigured.new
    end
    expect { described_class.new.perform(order) }.to raise_error(Invoice::DocumentPending)
  end

  it "retries a rendering failure rather than confirming without the invoice" do
    order = paid_order
    attempts = 0
    allow(PdfRenderer).to receive(:render) do
      attempts += 1
      raise Ferrum::TimeoutError if attempts == 1

      "%PDF-1.7 test"
    end

    perform_enqueued_jobs(only: [ described_class, MailDeliveryJob ]) do
      described_class.perform_later(order)
    end

    expect(attempts).to eq(2)
    expect(order.invoices.invoice.sole.pdf).to be_attached
    expect(ActionMailer::Base.deliveries.count).to eq(1)
    expect(ActionMailer::Base.deliveries.last.attachments).not_to be_empty
    expect(ApplicationJob::DOCUMENT_ERRORS).to include(Ferrum::TimeoutError)
  end
end
