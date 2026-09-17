require "rails_helper"

RSpec.describe Orders::RegularPriceRefund, type: :model do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

  def paid_order(price_paise: 550_000, total_paise: price_paise, metadata: {})
    ticket_type = TicketType.find_by(slug: "conference-pass-regular") ||
      create(:ticket_type, slug: "conference-pass-regular", price_paise: 550_000)
    order = create(:order, :paid, total_paise:, metadata:)
    ticket = create(:ticket, order:, ticket_type:, price_paise:)
    Invoice.issue_for!(order)
    create(:payment_event, order:, razorpay_payment_id: "pay_#{order.id}", amount_paise: total_paise)
    [ order, ticket ]
  end

  it "finds paid Regular tickets bought at ₹5,500" do
    eligible, = paid_order
    wrong_price, = paid_order(price_paise: 350_000)
    pending, = paid_order
    pending.update!(status: :pending)

    expect(described_class.eligible_orders).to contain_exactly(eligible)
    expect(described_class.eligible_orders).not_to include(wrong_price, pending)
  end

  it "refunds a flat ₹2,000 even when the ticket had a coupon" do
    order, ticket = paid_order(total_paise: 495_000, metadata: { "discount_paise" => 55_000 })
    adjustment = described_class.new(order)

    expect { adjustment.call }
      .to have_enqueued_job(InitiateRefundJob).with(kind_of(Refund), "pay_#{order.id}")

    refund = order.refunds.sole
    expect(refund).to have_attributes(
      amount_paise: 200_000,
      ticket_ids: [ ticket.id ],
      reason: "price_adjustment",
      reference: "regular-price-5500-to-3500:#{order.id}",
      status: "initiated"
    )
    expect(refund.line_items.sole).to include("price_paise" => 200_000, "discount_paise" => 0, "total_paise" => 200_000)
  end

  it "keeps the ticket valid when the price adjustment is processed" do
    order, ticket = paid_order
    refund = described_class.new(order).call
    event = create(:payment_event, order:, kind: "refund.processed", amount_paise: 200_000)

    credit_note = refund.process!(event)

    expect(ticket.reload.canceled_at).to be_nil
    expect(refund.reload).to be_processed
    expect(credit_note.line_items.sole.fetch("total_paise")).to eq(200_000)
  end

  it "does not create the same adjustment twice" do
    order, = paid_order
    adjustment = described_class.new(order)

    expect { 2.times { adjustment.call } }.to change(Refund, :count).by(1)
    expect(order.refunds.sole.amount_paise).to eq(200_000)
  end

  it "refunds ₹2,000 for every eligible ticket in the order" do
    ticket_type = create(:ticket_type, slug: "conference-pass-regular", price_paise: 550_000)
    order = create(:order, :paid, total_paise: 1_100_000)
    tickets = Array.new(2) { create(:ticket, order:, ticket_type:, price_paise: 550_000) }
    Invoice.issue_for!(order)
    create(:payment_event, order:, razorpay_payment_id: "pay_#{order.id}", amount_paise: order.total_paise)

    refund = described_class.new(order).call

    expect(refund.amount_paise).to eq(400_000)
    expect(refund.ticket_ids).to contain_exactly(*tickets.map(&:id))
  end

  it "does not leave a refund record behind when the payment cannot be identified" do
    order, = paid_order
    PaymentEvent.where(order:).delete_all

    expect { described_class.new(order).call }
      .to raise_error(ArgumentError, /exactly one Razorpay payment/)
    expect(order.refunds).to be_empty
  end

  it "never refunds more than the ticket actually cost" do
    order, = paid_order(total_paise: 150_000, metadata: { "discount_paise" => 400_000 })

    refund = described_class.new(order).call

    expect(refund.amount_paise).to eq(150_000)
    expect(refund.line_items.sole).to include("price_paise" => 200_000, "discount_paise" => 50_000, "total_paise" => 150_000)
  end

  it "leaves only the remaining ₹3,500 refundable if the ticket is later canceled" do
    order, ticket = paid_order
    adjustment = described_class.new(order).call
    adjustment.process!(create(:payment_event, order:, kind: "refund.processed", amount_paise: 200_000))

    cancellation = order.refund_tickets!([ ticket.id ])

    expect(cancellation).to have_attributes(amount_paise: 350_000, reason: "ticket_cancellation")
    expect(cancellation.line_items.sole).to include("price_paise" => 350_000, "discount_paise" => 0, "total_paise" => 350_000)
  end
end
