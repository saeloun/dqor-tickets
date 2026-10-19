require "rails_helper"

RSpec.describe ProcessRefundJob, type: :job do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

  it "cancels selected tickets, attaches a credit note, and enqueues email" do
    order = create(:order, :paid)
    selected = create(:ticket, order:)
    untouched = create(:ticket, order:)
    Invoice.issue_for!(order)
    refund = create(:refund, order:, razorpay_refund_id: "rfnd_test", amount_paise: selected.price_paise, ticket_ids: [ selected.id ])
    event = create(:payment_event, order:, kind: "refund.processed", amount_paise: refund.amount_paise)

    expect { described_class.perform_now(refund.id, event.id) }
      .to have_enqueued_mail(OrderMailer, :refund_note)

    expect(selected.reload.canceled_at).to be_present
    expect(untouched.reload.canceled_at).to be_nil
    expect(refund.reload.status).to eq("processed")
    expect(order.invoices.credit_note.sole.pdf).to be_attached
  end

  it "does not cancel the ticket for a price_adjustment refund and sends the price-drop email" do
    order = create(:order, :paid, total_paise: 550_000)
    ticket_type = create(:ticket_type, price_paise: 550_000)
    ticket = create(:ticket, order:, ticket_type:, price_paise: 550_000)
    Invoice.issue_for!(order)
    ticket_type.update!(price_paise: 450_000)
    refund = create(:refund, order:, kind: "price_adjustment", razorpay_refund_id: "rfnd_adj",
                     amount_paise: 100_000, ticket_ids: [ ticket.id ], ticket_amounts_paise: { ticket.id.to_s => 100_000 })
    event = create(:payment_event, order:, kind: "refund.processed", amount_paise: refund.amount_paise)

    expect { described_class.perform_now(refund.id, event.id) }
      .to have_enqueued_mail(OrderMailer, :price_adjustment_refund_note)

    expect(ticket.reload.canceled_at).to be_nil
    expect(refund.reload.status).to eq("processed")
    expect(order.invoices.credit_note.sole.line_items.sole.fetch("total_paise")).to eq(100_000)
  end

  it "retries after a transient document failure without duplicating the credit note or email" do
    order = create(:order, :paid)
    selected = create(:ticket, order:)
    Invoice.issue_for!(order)
    refund = create(:refund, order:, razorpay_refund_id: "rfnd_retry", amount_paise: selected.price_paise, ticket_ids: [ selected.id ])
    event = create(:payment_event, order:, kind: "refund.processed", amount_paise: refund.amount_paise)
    attempts = 0
    allow(PdfRenderer).to receive(:render) do
      attempts += 1
      raise Net::OpenTimeout, "timed out" if attempts == 1

      "%PDF-1.7 test"
    end

    expect do
      perform_enqueued_jobs do
        described_class.perform_later(refund.id, event.id)
      end
    end.to change(ActionMailer::Base.deliveries, :count).by(1)

    expect(attempts).to eq(2)
    expect(order.invoices.credit_note.count).to eq(1)
    expect(refund.reload).to have_attributes(status: "processed")
  end
end
