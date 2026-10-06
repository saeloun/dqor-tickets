require "rails_helper"

RSpec.describe ConferenceInventory do
  let!(:regular) { create(:ticket_type, slug: "conference-pass-regular", capacity: nil) }
  let!(:late) { create(:ticket_type, slug: "conference-pass-late-bird", capacity: nil) }
  let!(:supporter) { create(:ticket_type, slug: "supporter-pass", capacity: nil) }
  let!(:comp) { create(:ticket_type, slug: "complimentary-pass", hidden: true, price_paise: 0, capacity: nil) }

  def reserve(type, quantity:, status: :paid, expires_at: 30.minutes.from_now, canceled: false)
    order = create(:order, status:, expires_at:)
    quantity.times { create(:ticket, ticket_type: type, order:, canceled_at: (Time.current if canceled)) }
    order
  end

  def checkout(items)
    Orders::Checkout.call(order_attributes: { email: "capacity@example.test", buyer_name: "Capacity Buyer" }, items:)
  end

  it "combines paid tiers, valid comps and unexpired holds in one 200 seat pool" do
    reserve(regular, quantity: 197)
    reserve(supporter, quantity: 1)
    reserve(comp, quantity: 1)
    reserve(late, quantity: 1, status: :pending)
    expect(described_class.available_quantity).to eq(0)
    expect(described_class.confirmed.count).to eq(199)
    expect(regular.available_quantity).to eq(0)
    expect { checkout([ { ticket_type: late, quantity: 1 } ]) }.to raise_error(Orders::Checkout::SoldOut)
    expect { Order.issue_comps!(emails: "comp@example.test") }.to raise_error(Order::InsufficientAvailability)
  end

  it "allows the last comp but refuses an atomic batch larger than the remaining pool" do
    reserve(regular, quantity: 199)
    expect { Order.issue_comps!(emails: "first@example.test\nsecond@example.test") }.to raise_error(Order::InsufficientAvailability)
    expect(Order.count).to eq(1)
    expect(Order.issue_comps!(emails: "last@example.test").first).to be_paid
    expect(described_class.available_quantity).to eq(0)
  end

  it "shares the last seat with the existing all-talks supporter pass" do
    reserve(comp, quantity: 199)
    checkout([ { ticket_type: supporter, quantity: 1 } ])
    expect(supporter.available_quantity).to eq(0)
    expect { checkout([ { ticket_type: regular, quantity: 1 } ]) }.to raise_error(Orders::Checkout::SoldOut)
    expect { Order.issue_comps!(emails: "supporter-boundary@example.test") }.to raise_error(Order::InsufficientAvailability)
  end

  it "sums mixed tiers before creating an order" do
    reserve(regular, quantity: 199)
    expect { checkout([ { ticket_type: regular, quantity: 1 }, { ticket_type: late, quantity: 1 } ]) }.to raise_error(Orders::Checkout::SoldOut)
    expect(Order.count).to eq(1)
    checkout([ { ticket_type: late, quantity: 1 } ])
    expect(described_class.available_quantity).to eq(0)
  end

  it "releases canceled tickets and expired holds while retaining a pending refund obligation" do
    reserve(regular, quantity: 190)
    reserve(late, quantity: 3, status: :pending, expires_at: 1.second.ago)
    reserve(late, quantity: 2, status: :expired)
    reserve(late, quantity: 2, status: :canceled)
    reserve(comp, quantity: 1, canceled: true)
    refunded = reserve(regular, quantity: 1, canceled: true)
    create(:refund, order: refunded, status: :processed, ticket_ids: refunded.tickets.ids)
    refund_pending = reserve(regular, quantity: 1)
    create(:refund, order: refund_pending, status: :initiated, ticket_ids: refund_pending.tickets.ids)
    reserve(comp, quantity: 1, status: :pending, expires_at: nil)
    expect(described_class.available_quantity).to eq(9)
    expect(described_class.confirmed.count).to eq(191)
  end

  it "does not count or block Rails Girls, Explore or another event" do
    reserve(regular, quantity: 200)
    [ "rails-girls-pune", "explore-pune-day" ].each do |slug|
      type = create(:ticket_type, slug:, capacity: nil)
      expect(type.available_quantity).to eq(Float::INFINITY)
      expect { checkout([ { ticket_type: type, quantity: 1 } ]) }.to change(Order, :count).by(1)
    end
    organization = Organization.create!(name: "Other", slug: "capacity-other")
    event = Event.create!(organization:, title: "Other", slug: "other", timezone: "Asia/Kolkata")
    other = create(:ticket_type, slug: "conference-pass-other", event_id: event.id, capacity: nil, price_paise: 0, hidden: true, active: false)
    user = create(:user_for_free_pilot)
    owned_order = create(:order, :paid, event_id: event.id, user_id: user.id, total_paise: 0)
    5.times { create(:ticket, order: owned_order, ticket_type: other, event_id: event.id, price_paise: 0) }
    expect(other.available_quantity).to eq(Float::INFINITY)
    expect(described_class.confirmed.count).to eq(200)
  end

  it "rechecks the shared pool for an expired payment even when its tier remains unlimited" do
    expired = reserve(late, quantity: 1, status: :expired, expires_at: 1.second.ago)
    reserve(regular, quantity: 200)
    payment = create(:payment_event, order: expired)
    expect { expired.mark_paid!(payment) }.to raise_error(Order::InsufficientAvailability)
    expect(expired.reload).to be_expired
  end

  it "sums the whole expired basket and rechecks orders without a hold expiry" do
    expired = reserve(late, quantity: 1, status: :expired)
    create(:ticket, order: expired, ticket_type: regular)
    reserve(comp, quantity: 199)
    expect { expired.mark_paid!(create(:payment_event, order: expired)) }.to raise_error(Order::InsufficientAvailability)
    unheld = reserve(late, quantity: 2, status: :pending, expires_at: nil)
    expect { unheld.mark_paid!(create(:payment_event, order: unheld)) }.to raise_error(Order::InsufficientAvailability)
  end

  it "preserves a valid existing hold even if old obligations already exceed the new cap" do
    held = reserve(regular, quantity: 1, status: :pending)
    reserve(comp, quantity: 200)
    expect(held.mark_paid!(create(:payment_event, order: held))).to be(true)
    expect(described_class.confirmed.count).to eq(201)
    expect { checkout([ { ticket_type: late, quantity: 1 } ]) }.to raise_error(Orders::Checkout::SoldOut)
    expect { Order.issue_comps!(emails: "over-cap@example.test") }.to raise_error(Order::InsufficientAvailability)
  end

  it "confirms an existing hold at capacity and permits late payment when inventory is available" do
    held = reserve(regular, quantity: 1, status: :pending)
    reserve(comp, quantity: 199)
    expect(held.mark_paid!(create(:payment_event, order: held))).to be(true)
    expect(held.mark_paid!(held.payment_events.first)).to be(false)
    expect(described_class.confirmed.count).to eq(200)
    held.tickets.update_all(canceled_at: Time.current)
    expired = reserve(late, quantity: 1, status: :expired)
    expect(expired.mark_paid!(create(:payment_event, order: expired))).to be(true)
    expect(described_class.confirmed.count).to eq(200)
  end
end
