require "rails_helper"

RSpec.describe "Price adjustment refund safety", type: :model do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

  def purchase(discount: 0, count: 1, price: 550_000, **attributes)
    type = create(:ticket_type, price_paise: price)
    order = create(:order, :paid, total_paise: price * count - discount, metadata: { "discount_paise" => discount }, **attributes)
    tickets = create_list(:ticket, count, order:, ticket_type: type, price_paise: price)
    Invoice.issue_for!(order)
    create(:payment_event, order:, razorpay_payment_id: "pay_safety")
    type.update!(price_paise: 450_000)
    [ order, tickets, type ]
  end

  def process(refund)
    event = create(:payment_event, order: refund.order, kind: "refund.processed", amount_paise: refund.amount_paise)
    refund.process!(event)
  end

  it "compares the current catalog price to captured per-ticket net amounts" do
    order, tickets, = purchase(discount: 500_000, count: 2)
    expect(order.price_adjustment_breakdown(tickets.map(&:id))).to eq(tickets.last.id.to_s => 100_000)
  end

  it "never refunds a zero-net discounted ticket from another ticket's payment" do
    order, tickets, = purchase(discount: 550_000, count: 2)
    refund = order.apply_price_adjustment_refund!(tickets.map(&:id))
    expect(refund.ticket_amounts_paise).to eq(tickets.last.id.to_s => 100_000)
  end

  it "excludes processed one-time adjustments from the dry run" do
    order, tickets, = purchase
    process(order.apply_price_adjustment_refund!(tickets.map(&:id)))
    expect(order.price_adjustment_breakdown(tickets.map(&:id))).to be_empty
  end

  it "waits for an unresolved adjustment before admitting cancellation" do
    order, tickets, = purchase
    order.apply_price_adjustment_refund!(tickets.map(&:id))
    expect { order.refund_tickets!(tickets.map(&:id)) }.to raise_error(Refund::AlreadyRefunded, /unresolved/)
    expect(order.refunds.count).to eq(1)
  end

  it "reserves a legacy cancellation with empty allocations before its ticket is canceled" do
    order, tickets, = purchase
    create(:refund, order:, ticket_ids: tickets.map(&:id), amount_paise: 550_000, status: "initiated", ticket_amounts_paise: {})
    expect(Refund.refunded_paise_for(tickets.first)).to eq(550_000)
    expect(order.price_adjustment_breakdown(tickets.map(&:id))).to be_empty
    expect { order.apply_price_adjustment_refund!(tickets.map(&:id)) }.to raise_error(Refund::AlreadyRefunded)
  end

  it "blocks an ambiguous legacy allocation rather than treating it as zero" do
    order, tickets, = purchase
    create(:refund, order:, ticket_ids: tickets.map(&:id), amount_paise: 1, status: "initiated", ticket_amounts_paise: {})
    expect { Refund.refunded_paise_for(tickets.first) }.to raise_error(Refund::AlreadyRefunded, /allocation/)
  end

  it "does not enqueue adjustments below the gateway minimum" do
    order, tickets, type = purchase
    type.update!(price_paise: 549_950)
    expect(order.price_adjustment_breakdown(tickets.map(&:id))).to be_empty
    expect { order.apply_price_adjustment_refund!(tickets.map(&:id)) }.to raise_error(ArgumentError, /no eligible/)
    expect(order.refunds.reload).to be_empty
  end

  it "rolls back reservation and audit when durable enqueue fails" do
    order, tickets, = purchase
    allow(InitiateRefundJob).to receive(:perform_later).and_return(false)
    expect { order.apply_price_adjustment_refund!(tickets.map(&:id)) }.to raise_error(ActiveJob::EnqueueError)
    expect(order.refunds.reload).to be_empty
    expect(order.payment_events.where(kind: "price_adjustment_recorded")).to be_empty
  end

  it "preserves every original tax component across an adjustment and cancellation" do
    order, tickets, type = purchase
    type.update!(price_paise: 449_998)
    invoice = order.invoices.invoice.sole
    adjustment = order.apply_price_adjustment_refund!(tickets.map(&:id))
    process(adjustment)
    cancellation = order.refund_tickets!(tickets.map(&:id))
    process(cancellation)
    lines = invoice.credit_notes.flat_map(&:line_items)
    %w[total_paise taxable cgst sgst igst].each do |key|
      expect(lines.sum { |line| line.fetch(key) }).to eq(invoice.line_items.sole.fetch(key))
    end
  end

  it "issues a zero-remainder cancellation credit note after a full adjustment" do
    order, tickets, type = purchase
    type.update!(price_paise: 0)
    process(order.apply_price_adjustment_refund!(tickets.map(&:id)))
    cancellation = order.refund_tickets!(tickets.map(&:id))
    expect(cancellation.reload).to be_processed
    expect(cancellation.credit_note_number).to be_present
    expect(tickets.first.reload.canceled_at).to be_present
    expect(order.invoices.credit_note.last.line_items.sole.fetch("total_paise")).to eq(0)
  end

  it "records the initiating actor in the immutable audit event" do
    order, tickets, = purchase
    actor = create(:admin_user)
    order.apply_price_adjustment_refund!(tickets.map(&:id), actor:)
    expect(order.payment_events.find_by!(kind: "price_adjustment_recorded").raw).to include("actor_id" => actor.id)
  end
  it "credits mixed zero-net and paid cancellation lines without leaving documents pending" do
    order, tickets, = purchase(discount: 550_000, count: 2)
    cancellation = order.refund_tickets!(tickets.map(&:id))
    credit_note = process(cancellation)
    expect(cancellation.reload.credit_note_pending?).to be(false)
    expect(credit_note.line_items.map { |line| line.fetch("total_paise") }).to eq([ 0, 550_000 ])
    expect(tickets.map { |ticket| ticket.reload.canceled_at }).to all(be_present)
  end

  it "preserves original interstate tax across partial credits" do
    order, tickets, type = purchase(gstin: "29AAAAA0000A1Z5", billing_state_code: "29", metadata: { "billing_address" => "Test address", "billing_state_name" => "Karnataka" })
    original = order.invoices.invoice.sole
    original_lines = original.line_items
    type.update!(price_paise: 449_998)
    process(order.apply_price_adjustment_refund!(tickets.map(&:id)))
    process(order.refund_tickets!(tickets.map(&:id)))
    %w[total_paise taxable cgst sgst igst].each do |key|
      expect(original.credit_notes.flat_map(&:line_items).sum { |line| line.fetch(key) }).to eq(original_lines.sole.fetch(key))
    end
  end

  it "credits a mixed zero remainder and full ticket in the same cancellation" do
    order, tickets, type = purchase(count: 2)
    type.update!(price_paise: 0)
    process(order.apply_price_adjustment_refund!([ tickets.first.id ]))
    cancellation = order.refund_tickets!(tickets.map(&:id))
    credit_note = process(cancellation)
    expect(cancellation.reload.credit_note_pending?).to be(false)
    expect(credit_note.line_items.map { |line| line.fetch("total_paise") }).to eq([ 0, 550_000 ])
  end
  it "rejects two synthetic credit lines for the same ticket through the public issuer" do
    order, = purchase
    invoice = order.invoices.invoice.sole
    lines = [ 300_000, 260_000 ].map { |amount| Invoice.delta_line_item(invoice.line_items.sole, amount) }
    expect do
      Invoice.issue_for!(order, kind: :credit_note, refers_to: invoice, line_items: lines, allow_synthetic_credit_lines: true)
    end.to raise_error(ArgumentError)
    expect(invoice.credit_notes).to be_empty
  end

  it "rejects duplicate ticket credit lines during direct model creation" do
    order, = purchase
    invoice = order.invoices.invoice.sole
    lines = [ 300_000, 260_000 ].map { |amount| Invoice.delta_line_item(invoice.line_items.sole, amount) }
    attributes = invoice.attributes.except("id", "created_at", "updated_at").merge(
      "number" => "TCN/2627/000001", "kind" => "credit_note", "refers_to_id" => invoice.id, "line_items" => lines
    )
    expect { Invoice.create!(attributes.merge(allow_synthetic_credit_lines: true)) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(invoice.credit_notes).to be_empty
  end

  it "rejects a credit exceeding the cumulative per-ticket original amount" do
    order, = purchase
    invoice = order.invoices.invoice.sole
    first_line = Invoice.delta_line_item(invoice.line_items.sole, 100_002)
    Invoice.issue_for!(order, kind: :credit_note, refers_to: invoice, line_items: [ first_line ], allow_synthetic_credit_lines: true)
    excessive = Invoice.delta_line_item(invoice.line_items.sole, 450_000, credited_lines: [ first_line ])
    expect do
      Invoice.issue_for!(order, kind: :credit_note, refers_to: invoice, line_items: [ excessive ], allow_synthetic_credit_lines: true)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(invoice.credit_notes.count).to eq(1)
  end

  it "confirms the newly eligible subset of a mixed order while retaining one adjustment per ticket" do
    order, tickets, type = purchase(discount: 500_000, count: 2)
    first = order.apply_price_adjustment_refund!(tickets.map(&:id))
    expect(first.ticket_ids).to eq([ tickets.last.id ])
    process(first)
    type.update!(price_paise: 40_000)
    expect(order.price_adjustment_breakdown(tickets.map(&:id))).to eq(tickets.first.id.to_s => 10_000)
    second = order.apply_price_adjustment_refund!(tickets.map(&:id))
    expect(second.ticket_amounts_paise).to eq(tickets.first.id.to_s => 10_000)
    expect(order.price_adjustment_breakdown(tickets.map(&:id))).to be_empty
    expect { order.apply_price_adjustment_refund!(tickets.map(&:id)) }.to raise_error(Refund::AlreadyRefunded)
  end
end
