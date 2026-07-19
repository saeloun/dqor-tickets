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
end
