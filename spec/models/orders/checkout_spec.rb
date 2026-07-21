require "rails_helper"

RSpec.describe Orders::Checkout, type: :model do
  let(:order_attributes) { { email: "buyer@example.com", buyer_name: "Buyer" } }
  let(:ticket_type) { create(:ticket_type, capacity: 2) }

  def checkout(type = ticket_type, quantity: 1, **options)
    described_class.call(order_attributes:, items: [ { ticket_type: type, quantity: } ], **options)
  end

  it "creates a pending hold with ticket price and total snapshots" do
    order = checkout(quantity: 2)

    expect(order).to be_pending
    expect(order.expires_at).to be_within(2.seconds).of(30.minutes.from_now)
    expect(order.total_paise).to eq(700_000)
    expect(order.tickets.pluck(:price_paise)).to eq([ 350_000, 350_000 ])
    expect(order.tickets.pluck(:secret).uniq.size).to eq(2)
    expect(order.tickets).to all(have_attributes(attendee_name: nil, attendee_email: nil, assigned_at: nil))
    expect(order.tickets).to all(satisfy { |ticket| !ticket.assigned? && !ticket.pdf.attached? })
  end

  it "counts unexpired pending tickets against capacity" do
    checkout(quantity: 2)

    expect { checkout }.to raise_error(described_class::SoldOut)
    expect(ticket_type.available_quantity).to eq(0)
  end

  it "frees stock held by an expired pending order" do
    order = checkout(quantity: 2)
    order.update!(expires_at: 1.second.ago)

    expect { checkout(quantity: 2) }.to change(Order, :count).by(1)
    expect(ticket_type.available_quantity).to eq(0)
  end

  it "keeps paid tickets reserved after the hold time" do
    order = checkout(quantity: 2)
    order.update!(status: :paid, expires_at: 1.second.ago)

    expect { checkout }.to raise_error(described_class::SoldOut)
  end

  it "does not count canceled tickets" do
    order = checkout(quantity: 2)
    order.update!(status: :paid)
    order.tickets.first.update!(canceled_at: Time.current)

    expect { checkout }.to change(Order, :count).by(1)
  end

  it "rejects inactive and out-of-window ticket types" do
    ticket_type.update!(active: false)
    expect { checkout }.to raise_error(described_class::InvalidSelection, /not on sale/)

    ticket_type.update!(active: true, sales_start_at: 1.hour.from_now)
    expect { checkout }.to raise_error(described_class::InvalidSelection, /not on sale/)
  end

  it "enforces per-order quantity limits" do
    ticket_type.update!(min_per_order: 2, max_per_order: 3)

    expect { checkout(quantity: 1) }.to raise_error(described_class::InvalidSelection, /minimum/)
    expect { checkout(quantity: 4) }.to raise_error(described_class::InvalidSelection, /maximum/)
  end

  it "allows an add-on with a conference pass in the same order" do
    conference = create(:ticket_type, slug: "conference-pass-regular")
    add_on = create(:ticket_type, slug: "explore-pune-day", price_paise: 200_000, requires_conference_pass: true)

    order = described_class.call(
      order_attributes:,
      items: [ { ticket_type: conference, quantity: 1 }, { ticket_type: add_on, quantity: 1 } ]
    )

    expect(order.tickets.count).to eq(2)
  end

  it "allows an add-on with a matching existing paid conference order" do
    conference = create(:ticket_type, slug: "conference-pass-regular")
    paid_order = create(:order, :paid, email: "owner@example.com")
    create(:ticket, order: paid_order, ticket_type: conference)
    add_on = create(:ticket_type, slug: "explore-pune-day", requires_conference_pass: true)

    order = checkout(add_on, conference_order_code: paid_order.code, conference_order_email: "OWNER@example.com")

    expect(order.tickets.sole.ticket_type).to eq(add_on)
  end

  it "rejects an add-on without a conference pass" do
    add_on = create(:ticket_type, slug: "explore-pune-day", requires_conference_pass: true)

    expect { checkout(add_on) }.to raise_error(described_class::ConferencePassRequired)
  end
end
