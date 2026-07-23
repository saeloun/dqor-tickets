require "rails_helper"

# The GST tax invoice is the one artefact a buyer cannot re-create for themselves,
# so these examples pin the repair-and-redeliver contract between Order#attach_documents!,
# Order#deliver_confirmation! and Invoice.issue_for!.
RSpec.describe "Order document lifecycle", type: :model do
  before do
    allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")
    ActionMailer::Base.deliveries.clear
  end

  def paid_order(**attributes)
    create(:order, :paid, **attributes).tap { |order| create(:ticket, order:) }
  end

  def mail_jobs
    enqueued_jobs.count { |job| job[:job] == MailDeliveryJob }
  end

  describe "#attach_documents!" do
    it "issues the missing invoice for a paid order instead of silently skipping it" do
      order = paid_order
      expect(order.invoices).to be_empty

      expect { order.attach_documents! }.to change { order.invoices.invoice.count }.from(0).to(1)

      invoice = order.invoices.invoice.sole
      expect(invoice.pdf).to be_attached
      expect(invoice.pdf.download).to eq("%PDF-1.7 test")
      expect(invoice.line_items.sole).to include("ticket_id" => order.tickets.sole.id)
    end

    it "attaches the PDF to an invoice that was issued without one" do
      order = paid_order
      invoice = Invoice.issue_for!(order)
      expect(invoice.pdf).not_to be_attached

      order.attach_documents!

      expect(invoice.reload.pdf).to be_attached
      expect(order.invoices.invoice.count).to eq(1)
    end

    it "renders the invoice once however often it is called" do
      order = paid_order

      3.times { order.attach_documents! }

      expect(PdfRenderer).to have_received(:render).once
      expect(order.invoices.invoice.count).to eq(1)
    end

    it "is a no-op for every status other than paid" do
      %i[pending expired canceled].each do |status|
        order = create(:order, status:)
        create(:ticket, order:)

        expect(order.attach_documents!).to be_nil
        expect(order.invoices).to be_empty
      end

      expect(PdfRenderer).not_to have_received(:render)
    end

    it "surfaces a rendering failure instead of leaving the buyer with no invoice and no error" do
      order = paid_order
      allow(PdfRenderer).to receive(:render).and_raise(Ferrum::DeadBrowserError)

      expect { order.attach_documents! }.to raise_error(Ferrum::DeadBrowserError)
      expect(order.invoices.invoice.sole.pdf).not_to be_attached
      expect(ApplicationJob::DOCUMENT_ERRORS).to include(Ferrum::DeadBrowserError)
    end
  end

  describe "Invoice.issue_for!" do
    it "is idempotent" do
      order = paid_order

      first = Invoice.issue_for!(order)
      second = Invoice.issue_for!(order.reload)

      expect(second).to eq(first)
      expect(order.invoices.invoice.count).to eq(1)
      expect(Invoice.invoice.where(order:).pluck(:number)).to eq([ first.number ])
    end

    it "is backed by a database index so a second invoice cannot be inserted behind its back" do
      order = paid_order
      Invoice.issue_for!(order)

      expect do
        Invoice.create!(
          order:,
          number: "DQOR/2026-27/9999",
          issued_on: Date.current,
          buyer_snapshot: {},
          line_items: [],
          kind: :invoice
        )
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "leaves credit notes free of that index" do
      order = paid_order
      invoice = Invoice.issue_for!(order)

      first = Invoice.issue_for!(order, kind: :credit_note, refers_to: invoice, line_items: invoice.line_items)
      second = Invoice.issue_for!(order, kind: :credit_note, refers_to: invoice, line_items: invoice.line_items)

      expect(order.invoices.credit_note.count).to eq(2)
      expect([ first, second ].map(&:number).uniq.size).to eq(2)
    end
  end

  describe "#deliver_confirmation!" do
    it "sends the confirmation exactly once however often it is called" do
      order = paid_order

      results = Array.new(4) { order.deliver_confirmation! }

      expect(results).to eq([ true, false, false, false ])
      expect(mail_jobs).to eq(1)
      expect(PdfRenderer).to have_received(:render).once
      expect(order.reload.metadata).to include("confirmation_documents_pending" => false)
      expect(order.metadata["confirmation_enqueued_at"]).to be_present
    end

    it "re-sends a confirmation that went out while the documents were still pending" do
      order = paid_order

      expect(order.deliver_confirmation!(documents_pending: true)).to be(true)
      expect(order.reload.metadata).to include("confirmation_documents_pending" => true)
      expect(order.invoices).to be_empty

      # The regression: this used to return false forever, so the tax invoice was never sent.
      expect(order.deliver_confirmation!).to be(true)
      expect(order.reload.metadata).to include("confirmation_documents_pending" => false)
      expect(order.invoices.invoice.sole.pdf).to be_attached

      # ...and the door closes again once the real confirmation is out.
      expect(order.deliver_confirmation!).to be(false)
      expect(mail_jobs).to eq(2)
    end

    it "keeps the confirmation re-sendable for as long as the documents stay pending" do
      order = paid_order

      3.times { expect(order.deliver_confirmation!(documents_pending: true)).to be(true) }

      expect(order.reload.metadata).to include("confirmation_documents_pending" => true)
      expect(mail_jobs).to eq(3)
    end

    it "tells the mailer the documents are pending and skips rendering entirely" do
      order = paid_order
      Invoice.issue_for!(order)

      expect { expect(order.deliver_confirmation!(documents_pending: true)).to be(true) }
        .to have_enqueued_mail(OrderMailer, :confirmation).with(order, documents_pending: true)

      expect(order.reload.metadata).to include("confirmation_documents_pending" => true)
      expect(order.invoices.invoice.sole.pdf).not_to be_attached
      expect(PdfRenderer).not_to have_received(:render)
    end

    it "does not claim the confirmation was sent when the documents cannot be rendered" do
      order = paid_order
      allow(PdfRenderer).to receive(:render).and_raise(Ferrum::TimeoutError)

      expect { order.deliver_confirmation! }.to raise_error(Ferrum::TimeoutError)

      expect(order.reload.metadata).not_to include("confirmation_enqueued_at")
      expect(mail_jobs).to eq(0)
    end

    it "preserves unrelated metadata written by checkout" do
      order = paid_order(metadata: { "discount_paise" => 50_000, "coupon_ticket_type_id" => 7 })

      order.deliver_confirmation!(documents_pending: true)
      order.deliver_confirmation!

      expect(order.reload.metadata).to include(
        "discount_paise" => 50_000,
        "coupon_ticket_type_id" => 7,
        "confirmation_documents_pending" => false
      )
    end

    it "delivers the pending-documents mail first and the invoice-bearing mail second" do
      order = paid_order

      perform_enqueued_jobs(only: MailDeliveryJob) do
        order.deliver_confirmation!(documents_pending: true)
        order.deliver_confirmation!
      end

      degraded, final = ActionMailer::Base.deliveries.last(2)
      expect(degraded.attachments).to be_empty
      expect(degraded.body.encoded).to include("being prepared")
      expect(final.attachments.map(&:filename)).to contain_exactly(order.invoices.invoice.sole.pdf.filename.to_s)
      expect(final.body.encoded).to include("is attached")
    end
  end
end
