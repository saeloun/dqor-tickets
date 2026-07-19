require "rails_helper"

RSpec.describe Invoice, type: :model do
  def order_with_ticket(**attributes)
    order = create(:order, :paid, **attributes)
    create(:ticket, order:)
    order
  end

  it "numbers invoices sequentially within an Indian financial year" do
    first = described_class.issue_for!(order_with_ticket, issued_on: Date.new(2026, 4, 1))
    second = described_class.issue_for!(order_with_ticket, issued_on: Date.new(2027, 3, 31))

    expect(first.number).to eq("DQOR/2026-27/0001")
    expect(second.number).to eq("DQOR/2026-27/0002")
  end

  it "starts a new sequence at the April financial-year boundary" do
    march = described_class.issue_for!(order_with_ticket, issued_on: Date.new(2026, 3, 31))
    april = described_class.issue_for!(order_with_ticket, issued_on: Date.new(2026, 4, 1))

    expect(march.number).to eq("DQOR/2025-26/0001")
    expect(april.number).to eq("DQOR/2026-27/0001")
  end

  it "uses an independent credit-note prefix and reference" do
    order = order_with_ticket
    invoice = described_class.issue_for!(order, issued_on: Date.new(2026, 7, 19))
    credit_note = described_class.issue_for!(
      order,
      kind: :credit_note,
      refers_to: invoice,
      issued_on: Date.new(2026, 7, 20),
      line_items: invoice.line_items
    )

    expect(credit_note.number).to eq("DQOR-CN/2026-27/0001")
    expect(credit_note.refers_to).to eq(invoice)
  end

  it "snapshots buyer and reconciled GST line items" do
    order = order_with_ticket(gstin: "29AAAAA0000A1Z5", billing_state_code: "29")

    invoice = described_class.issue_for!(order, issued_on: Date.new(2026, 7, 19))

    expect(invoice.buyer_snapshot["gstin"]).to eq("29AAAAA0000A1Z5")
    expect(invoice.line_items.sole.values_at("total_paise", "taxable", "igst")).to eq([ 350_000, 296_610, 53_390 ])
  end

  it "cannot be destroyed" do
    invoice = described_class.issue_for!(order_with_ticket)

    expect { invoice.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
