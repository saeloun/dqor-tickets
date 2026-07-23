require "rails_helper"

RSpec.describe Refund, type: :model do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

  def paid_order(ticket_count: 1, price_paise: 350_000, capacity: 10, **attributes)
    ticket_type = create(:ticket_type, price_paise:, capacity:)
    order = create(:order, :paid, total_paise: price_paise * ticket_count, **attributes)
    tickets = Array.new(ticket_count) { create(:ticket, order:, ticket_type:, price_paise:) }
    [ order, tickets, ticket_type ]
  end

  def invoiced_lines_for(order, tickets)
    ids = Array(tickets).map(&:id)
    order.invoices.invoice.sole.line_items.select { |line| ids.include?(line.fetch("ticket_id")) }
  end

  def refund_for(order, tickets, amount_paise: nil, status: "initiated")
    create(
      :refund,
      order:,
      status:,
      ticket_ids: Array(tickets).map(&:id),
      amount_paise: amount_paise || invoiced_lines_for(order, tickets).sum { |line| line.fetch("total_paise") }
    )
  end

  def refund_event(refund, amount_paise: refund.amount_paise)
    create(:payment_event, order: refund.order, kind: "refund.processed", amount_paise:)
  end

  describe "validations" do
    it "requires an order" do
      refund = described_class.new(amount_paise: 100, status: "initiated")

      expect(refund).not_to be_valid
      expect(refund.errors[:order]).to be_present
    end

    it "requires a status" do
      refund = build(:refund, status: nil)

      expect(refund).not_to be_valid
      expect(refund.errors[:status]).to include("can't be blank")
    end

    it "rejects a negative amount" do
      refund = build(:refund, amount_paise: -1)

      expect(refund).not_to be_valid
      expect(refund.errors[:amount_paise]).to include("must be greater than or equal to 0")
    end

    it "allows a zero amount so complimentary tickets can be cancelled" do
      expect(build(:refund, amount_paise: 0)).to be_valid
    end

    it "defaults ticket_ids to an empty list" do
      expect(create(:refund).ticket_ids).to eq([])
    end
  end

  describe "#process! guards" do
    it "rejects a payment event that belongs to another order" do
      order, tickets, = paid_order
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets)
      foreign_event = create(:payment_event, kind: "refund.processed", amount_paise: refund.amount_paise)

      expect { refund.process!(foreign_event) }.to raise_error(ArgumentError, /belongs to another order/)
      expect(order.invoices.credit_note).to be_empty
      expect(refund.reload.status).to eq("initiated")
    end

    it "rejects a payment event whose amount is off by a single paisa" do
      order, tickets, = paid_order
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets)

      expect { refund.process!(refund_event(refund, amount_paise: refund.amount_paise + 1)) }
        .to raise_error(ArgumentError, /amount does not match refund/)
      expect(order.invoices.credit_note).to be_empty
      expect(tickets.first.reload.canceled_at).to be_nil
    end

    it "rejects a refund whose tickets are not on the invoice" do
      order, = paid_order
      Invoice.issue_for!(order)
      other_order, other_tickets, = paid_order
      refund = create(:refund, order:, status: "initiated", ticket_ids: [ other_tickets.first.id ], amount_paise: 350_000)
      _ = other_order

      expect { refund.process!(refund_event(refund)) }.to raise_error(ArgumentError, /no selected tickets/)
      expect(order.invoices.credit_note).to be_empty
    end

    it "rejects a refund with no tickets selected at all" do
      order, = paid_order
      Invoice.issue_for!(order)
      refund = create(:refund, order:, status: "initiated", ticket_ids: [], amount_paise: 0)

      expect { refund.process!(refund_event(refund)) }.to raise_error(ArgumentError, /no selected tickets/)
    end

    it "refuses to refund a single paisa more than the selected tickets are worth" do
      order, tickets, = paid_order
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets, amount_paise: 350_001)

      expect { refund.process!(refund_event(refund)) }.to raise_error(ArgumentError, /does not match selected tickets/)
      expect(order.invoices.credit_note).to be_empty
      expect(tickets.first.reload.canceled_at).to be_nil
      expect(refund.reload).to have_attributes(status: "initiated", credit_note_number: nil)
    end

    it "refuses to refund more than the whole order was invoiced for" do
      order, tickets, = paid_order(ticket_count: 2)
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets, amount_paise: order.total_paise * 2)

      expect(refund.amount_paise).to eq(1_400_000)
      expect { refund.process!(refund_event(refund)) }.to raise_error(ArgumentError, /does not match selected tickets/)
      expect(described_class.where(status: "processed").sum(:amount_paise)).to eq(0)
    end

    it "refuses to refund less than the selected tickets are worth" do
      order, tickets, = paid_order
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets, amount_paise: 349_999)

      expect { refund.process!(refund_event(refund)) }.to raise_error(ArgumentError, /does not match selected tickets/)
      expect(tickets.first.reload.canceled_at).to be_nil
    end

    it "refuses to refund a ticket at its face value when a coupon discounted it" do
      order, tickets, = paid_order(ticket_count: 2)
      order.update!(total_paise: 650_000, metadata: { "discount_paise" => 50_000 })
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets.first, amount_paise: 350_000)

      expect(invoiced_lines_for(order, tickets.first).sole.fetch("total_paise")).to eq(300_000)
      expect { refund.process!(refund_event(refund)) }.to raise_error(ArgumentError, /does not match selected tickets/)
    end
  end

  describe "#process! credit note issuance" do
    it "issues a credit note that refers to the original invoice and records its number" do
      order, tickets, = paid_order
      invoice = Invoice.issue_for!(order)
      refund = refund_for(order, tickets)

      credit_note = refund.process!(refund_event(refund))

      expect(credit_note).to have_attributes(kind: "credit_note", refers_to: invoice, order:)
      expect(credit_note.buyer_snapshot.fetch("email")).to eq(order.email)
      expect(refund.reload).to have_attributes(status: "processed", credit_note_number: credit_note.number)
      expect(order.invoices.credit_note.sole).to eq(credit_note)
    end

    it "numbers credit notes in their own sequence, separate from invoices" do
      travel_to(Date.new(2026, 7, 19)) do
        first_order, first_tickets, = paid_order
        first_invoice = Invoice.issue_for!(first_order)
        second_order, second_tickets, = paid_order
        second_invoice = Invoice.issue_for!(second_order)

        first_note = refund_for(first_order, first_tickets).then { |refund| refund.process!(refund_event(refund)) }
        second_note = refund_for(second_order, second_tickets).then { |refund| refund.process!(refund_event(refund)) }

        expect([ first_invoice.number, second_invoice.number ]).to eq([ "DQOR/2026-27/0001", "DQOR/2026-27/0002" ])
        expect([ first_note.number, second_note.number ]).to eq([ "DQOR-CN/2026-27/0001", "DQOR-CN/2026-27/0002" ])
      end
    end

    it "issues credit notes in the financial year they are raised in, not the invoice's" do
      order, tickets, = paid_order
      travel_to(Date.new(2027, 3, 31)) { Invoice.issue_for!(order) }
      refund = refund_for(order, tickets)

      credit_note = travel_to(Date.new(2027, 4, 1)) { refund.process!(refund_event(refund)) }

      expect(order.invoices.invoice.sole.number).to eq("DQOR/2026-27/0001")
      expect(credit_note.number).to eq("DQOR-CN/2027-28/0001")
      expect(credit_note.issued_on).to eq(Date.new(2027, 4, 1))
    end

    it "copies only the refunded lines, in exact paise, with their GST split" do
      order, tickets, = paid_order(ticket_count: 3)
      Invoice.issue_for!(order)
      refunded, kept, = tickets
      refund = refund_for(order, refunded)

      credit_note = refund.process!(refund_event(refund))

      expect(refund.amount_paise).to eq(350_000)
      expect(credit_note.line_items.size).to eq(1)
      expect(credit_note.line_items.sole).to include(
        "ticket_id" => refunded.id,
        "price_paise" => 350_000,
        "discount_paise" => 0,
        "total_paise" => 350_000,
        "taxable" => 296_610,
        "cgst" => 26_695,
        "sgst" => 26_695,
        "igst" => 0
      )
      expect(credit_note.line_items.map { |line| line.fetch("ticket_id") }).not_to include(kept.id)
    end

    it "reverses exactly the discounted amount for a couponed ticket" do
      order, tickets, = paid_order(ticket_count: 2)
      order.update!(total_paise: 650_000, metadata: { "discount_paise" => 50_000 })
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets.first)

      credit_note = refund.process!(refund_event(refund))

      expect(refund.amount_paise).to eq(300_000)
      expect(credit_note.line_items.sole).to include(
        "price_paise" => 350_000,
        "discount_paise" => 50_000,
        "total_paise" => 300_000,
        "taxable" => 254_237,
        "cgst" => 22_882,
        "sgst" => 22_881,
        "igst" => 0
      )
    end

    it "reverses IGST for a GST-registered buyer outside Maharashtra" do
      order, tickets, = paid_order(gstin: "29AAAAA0000A1Z5", billing_state_code: "29")
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets)

      credit_note = refund.process!(refund_event(refund))

      expect(credit_note.line_items.sole).to include(
        "total_paise" => 350_000,
        "taxable" => 296_610,
        "cgst" => 0,
        "sgst" => 0,
        "igst" => 53_390
      )
    end

    it "keeps every credit note line balanced to the paise" do
      order, tickets, = paid_order(ticket_count: 2, price_paise: 333_333)
      order.update!(total_paise: 666_666)
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets)

      credit_note = refund.process!(refund_event(refund))

      credit_note.line_items.each do |line|
        expect(line.values_at("taxable", "cgst", "sgst", "igst")).to all(be_a(Integer))
        expect(line.fetch("taxable") + line.fetch("cgst") + line.fetch("sgst") + line.fetch("igst"))
          .to eq(line.fetch("total_paise"))
      end
      expect(credit_note.line_items.sum { |line| line.fetch("total_paise") }).to eq(666_666)
    end

    it "credits the full order total when every ticket is refunded" do
      order, tickets, = paid_order(ticket_count: 3)
      invoice = Invoice.issue_for!(order)
      refund = refund_for(order, tickets)

      credit_note = refund.process!(refund_event(refund))

      expect(refund.amount_paise).to eq(order.total_paise)
      expect(credit_note.line_items.sum { |line| line.fetch("total_paise") }).to eq(1_050_000)
      expect(credit_note.line_items).to eq(invoice.line_items)
    end

    it "credits less than the order total on a partial refund" do
      order, tickets, = paid_order(ticket_count: 3)
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets.take(2))

      credit_note = refund.process!(refund_event(refund))

      expect(refund.amount_paise).to eq(700_000)
      expect(order.total_paise - credit_note.line_items.sum { |line| line.fetch("total_paise") }).to eq(350_000)
    end

    it "issues a credit note for a zero-amount complimentary refund without touching a gateway" do
      order, tickets, = paid_order(price_paise: 0)
      order.update!(total_paise: 0)
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets)

      credit_note = refund.process!(refund_event(refund))

      expect(refund.reload).to have_attributes(status: "processed", amount_paise: 0)
      expect(credit_note.line_items.sole.fetch("total_paise")).to eq(0)
      expect(a_request(:any, /api\.razorpay\.com/)).not_to have_been_made
    end
  end

  describe "#process! ticket lifecycle" do
    it "cancels only the refunded tickets" do
      order, tickets, = paid_order(ticket_count: 3)
      Invoice.issue_for!(order)
      refunded, kept_one, kept_two = tickets
      refund = refund_for(order, refunded)

      freeze_time do
        refund.process!(refund_event(refund))

        expect(refunded.reload.canceled_at).to eq(Time.current)
      end
      expect(kept_one.reload.canceled_at).to be_nil
      expect(kept_two.reload.canceled_at).to be_nil
    end

    it "releases inventory held by the refunded tickets" do
      order, tickets, ticket_type = paid_order(ticket_count: 3, capacity: 10)
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets.take(2))

      expect { refund.process!(refund_event(refund)) }
        .to change { ticket_type.reload.available_quantity }.from(7).to(9)
    end

    it "stops a refunded ticket from being checked in" do
      order, tickets, = paid_order
      Invoice.issue_for!(order)
      ticket = tickets.first
      refund = refund_for(order, ticket)

      refund.process!(refund_event(refund))

      expect { ticket.reload.check_in!(Date.current) }.to raise_error(Ticket::Canceled, /canceled ticket/)
      expect(ticket.reload.checked_in_at).to eq({})
    end

    it "stops a refunded ticket from being reassigned to a new attendee" do
      order, tickets, = paid_order
      Invoice.issue_for!(order)
      ticket = tickets.first
      refund = refund_for(order, ticket)

      refund.process!(refund_event(refund))

      expect { ticket.reload.assign!(attendee_name: "Grace", attendee_email: "grace@example.com") }
        .to raise_error(Ticket::Canceled)
    end

    it "still cancels a ticket that was already checked in" do
      order, tickets, = paid_order
      Invoice.issue_for!(order)
      ticket = tickets.first
      ticket.check_in!(Date.current)
      refund = refund_for(order, ticket)

      refund.process!(refund_event(refund))

      expect(ticket.reload.canceled_at).to be_present
      expect(ticket.checked_in_at.keys).to eq([ Date.current.iso8601 ])
    end
  end

  describe "#process! idempotency" do
    it "returns the same credit note without cancelling or crediting twice" do
      order, tickets, = paid_order(ticket_count: 2)
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets.first)
      event = refund_event(refund)

      first = refund.process!(event)
      canceled_at = tickets.first.reload.canceled_at
      second = refund.process!(event)

      expect(second).to eq(first)
      expect(order.invoices.credit_note.count).to eq(1)
      expect(tickets.first.reload.canceled_at).to eq(canceled_at)
      expect(described_class.where(status: "processed").sum(:amount_paise)).to eq(350_000)
    end

    it "still validates the payment event before short-circuiting a processed refund" do
      order, tickets, = paid_order
      Invoice.issue_for!(order)
      refund = refund_for(order, tickets)
      refund.process!(refund_event(refund))

      expect { refund.process!(refund_event(refund, amount_paise: 1)) }
        .to raise_error(ArgumentError, /amount does not match refund/)
      expect(order.invoices.credit_note.count).to eq(1)
    end
  end

  describe "known gaps" do
    it "BUG: re-refunds an already cancelled ticket, taking the order past a full refund" do
      order, tickets, = paid_order
      Invoice.issue_for!(order)
      ticket = tickets.first

      first = refund_for(order, ticket)
      first.process!(refund_event(first))

      second = refund_for(order, ticket)
      second_note = second.process!(refund_event(second))

      expect(second_note.number).to eq("DQOR-CN/#{Invoice.financial_year(Date.current)}/0002")
      expect(order.invoices.credit_note.count).to eq(2)
      expect(described_class.where(status: "processed").sum(:amount_paise)).to eq(700_000)
      expect(order.total_paise).to eq(350_000)
    end

    it "BUG: raises a bare RecordNotFound when the order was never invoiced" do
      order = create(:order)
      ticket = create(:ticket, order:)
      refund = create(:refund, order:, status: "initiated", ticket_ids: [ ticket.id ], amount_paise: order.total_paise)

      expect { refund.process!(refund_event(refund)) }.to raise_error(ActiveRecord::RecordNotFound, /Invoice/)
      expect(ticket.reload.canceled_at).to be_nil
    end

    it "accepts any status string because there is no state machine" do
      refund = create(:refund, status: "banana")

      expect(refund.reload.status).to eq("banana")
    end
  end
end
