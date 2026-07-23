require "rails_helper"

RSpec.describe TicketType, type: :model do
  let(:ticket_type) { create(:ticket_type, capacity: 10) }

  def hold(type = ticket_type, quantity: 1, status: :pending, expires_at: 30.minutes.from_now, canceled: false)
    order = create(:order, status:, expires_at:)
    quantity.times { create(:ticket, order:, ticket_type: type, canceled_at: (Time.current if canceled)) }
    order
  end

  describe "validations" do
    it "requires a name and a unique slug" do
      create(:ticket_type, slug: "conference-pass-regular")

      expect(build(:ticket_type, name: nil)).not_to be_valid
      expect(build(:ticket_type, slug: nil)).not_to be_valid
      expect(build(:ticket_type, slug: "conference-pass-regular")).not_to be_valid
      expect(build(:ticket_type, slug: "conference-pass-early-bird")).to be_valid
    end

    it "allows a free ticket but rejects a negative price or position" do
      expect(build(:ticket_type, price_paise: 0)).to be_valid
      expect(build(:ticket_type, price_paise: -1)).not_to be_valid
      expect(build(:ticket_type, position: 0)).to be_valid
      expect(build(:ticket_type, position: -1)).not_to be_valid
    end

    it "treats a nil capacity as unlimited and allows a zero capacity" do
      expect(build(:ticket_type, capacity: nil)).to be_valid
      expect(build(:ticket_type, capacity: 0)).to be_valid
      expect(build(:ticket_type, capacity: -1)).not_to be_valid
    end

    it "requires positive order limits" do
      expect(build(:ticket_type, min_per_order: 0)).not_to be_valid
      expect(build(:ticket_type, max_per_order: 0)).not_to be_valid
      expect(build(:ticket_type, max_per_order: nil)).to be_valid
    end

    it "rejects a maximum below the minimum but allows them to be equal" do
      expect(build(:ticket_type, min_per_order: 2, max_per_order: 1)).not_to be_valid
      expect(build(:ticket_type, min_per_order: 2, max_per_order: 2)).to be_valid
    end

    it "rejects a sales window that ends before it starts" do
      start_at = Time.current

      expect(build(:ticket_type, sales_start_at: start_at, sales_end_at: start_at - 1.second)).not_to be_valid
      expect(build(:ticket_type, sales_start_at: start_at, sales_end_at: start_at)).to be_valid
      expect(build(:ticket_type, sales_start_at: nil, sales_end_at: start_at)).to be_valid
    end
  end

  describe "associations" do
    it "refuses to destroy a type that has tickets" do
      hold

      expect { ticket_type.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
      expect(described_class.exists?(ticket_type.id)).to be(true)
    end

    it "nullifies coupons scoped to a destroyed type" do
      coupon = create(:coupon, ticket_type:)

      ticket_type.destroy

      expect(coupon.reload.ticket_type_id).to be_nil
    end
  end

  describe "#available_quantity" do
    it "is the full capacity when nothing has been sold" do
      expect(ticket_type.available_quantity).to eq(10)
    end

    it "consumes stock for paid orders" do
      hold(quantity: 3, status: :paid)

      expect(ticket_type.available_quantity).to eq(7)
    end

    it "keeps paid stock consumed even once the hold window has passed" do
      hold(quantity: 3, status: :paid, expires_at: 1.hour.ago)

      expect(ticket_type.available_quantity).to eq(7)
    end

    it "holds stock for unexpired pending orders" do
      hold(quantity: 4, status: :pending, expires_at: 5.minutes.from_now)

      expect(ticket_type.available_quantity).to eq(6)
    end

    it "releases stock held by an expired pending order" do
      hold(quantity: 4, status: :pending, expires_at: 1.second.ago)

      expect(ticket_type.available_quantity).to eq(10)
    end

    it "releases stock at the exact expiry instant" do
      now = Time.current
      hold(quantity: 4, status: :pending, expires_at: now)

      expect(ticket_type.available_quantity(at: now)).to eq(10)
      expect(ticket_type.available_quantity(at: now - 1.second)).to eq(6)
    end

    it "releases stock for orders already marked expired or canceled" do
      hold(quantity: 2, status: :expired, expires_at: 1.minute.ago)
      hold(quantity: 2, status: :canceled)

      expect(ticket_type.available_quantity).to eq(10)
    end

    it "releases stock for a pending order with no expiry" do
      hold(quantity: 4, status: :pending, expires_at: nil)

      expect(ticket_type.available_quantity).to eq(10)
    end

    it "does not consume stock for canceled tickets on a paid order" do
      order = hold(quantity: 3, status: :paid)
      order.tickets.first.update!(canceled_at: Time.current)

      expect(ticket_type.available_quantity).to eq(8)
    end

    it "does not consume stock for canceled tickets on a live pending order" do
      order = hold(quantity: 3, status: :pending)
      order.tickets.update_all(canceled_at: Time.current)

      expect(ticket_type.available_quantity).to eq(10)
    end

    it "counts only tickets of this type" do
      other = create(:ticket_type, capacity: 10)
      hold(quantity: 2, status: :paid)
      hold(other, quantity: 5, status: :paid)

      expect(ticket_type.available_quantity).to eq(8)
      expect(other.available_quantity).to eq(5)
    end

    it "evaluates holds against the supplied time" do
      hold(quantity: 4, status: :pending, expires_at: 10.minutes.from_now)

      expect(ticket_type.available_quantity(at: 5.minutes.from_now)).to eq(6)
      expect(ticket_type.available_quantity(at: 20.minutes.from_now)).to eq(10)
    end

    it "is unlimited when capacity is nil, no matter how much is sold" do
      unlimited = create(:ticket_type, capacity: nil)
      hold(unlimited, quantity: 25, status: :paid)

      expect(unlimited.available_quantity).to eq(Float::INFINITY)
      expect(unlimited.available_quantity).to be > 1_000_000
    end

    it "is zero for a zero capacity type" do
      expect(create(:ticket_type, capacity: 0).available_quantity).to eq(0)
    end

    it "reaches exactly zero at capacity" do
      limited = create(:ticket_type, capacity: 3)
      hold(limited, quantity: 3, status: :paid)

      expect(limited.available_quantity).to eq(0)
    end

    it "goes negative when stock is issued past capacity" do
      limited = create(:ticket_type, capacity: 3)
      hold(limited, quantity: 4, status: :paid)

      expect(limited.available_quantity).to eq(-1)
    end

    it "combines paid and pending holds and ignores released ones" do
      hold(quantity: 2, status: :paid)
      hold(quantity: 3, status: :pending, expires_at: 5.minutes.from_now)
      hold(quantity: 4, status: :pending, expires_at: 1.minute.ago)
      hold(quantity: 1, status: :canceled)

      expect(ticket_type.available_quantity).to eq(5)
    end
  end

  describe "#purchasable?" do
    it "is true for an active type with no sales window" do
      expect(ticket_type).to be_purchasable
    end

    it "is false when inactive" do
      ticket_type.update!(active: false)

      expect(ticket_type).not_to be_purchasable
    end

    it "is false before the window opens and true from the opening instant" do
      opens_at = Time.current
      ticket_type.update!(sales_start_at: opens_at)

      expect(ticket_type.purchasable?(at: opens_at - 1.second)).to be(false)
      expect(ticket_type.purchasable?(at: opens_at)).to be(true)
      expect(ticket_type.purchasable?(at: opens_at + 1.second)).to be(true)
    end

    it "is true up to and including the closing instant" do
      closes_at = Time.current
      ticket_type.update!(sales_end_at: closes_at)

      expect(ticket_type.purchasable?(at: closes_at - 1.second)).to be(true)
      expect(ticket_type.purchasable?(at: closes_at)).to be(true)
      expect(ticket_type.purchasable?(at: closes_at + 1.second)).to be(false)
    end

    it "is false outside a bounded window even when active" do
      ticket_type.update!(sales_start_at: 1.hour.from_now, sales_end_at: 2.hours.from_now)

      expect(ticket_type).not_to be_purchasable
      expect(ticket_type.purchasable?(at: 90.minutes.from_now)).to be(true)
    end

    it "is inactive-first: an inactive type inside its window is still not purchasable" do
      ticket_type.update!(active: false, sales_start_at: 1.hour.ago, sales_end_at: 1.hour.from_now)

      expect(ticket_type).not_to be_purchasable
    end

    it "ignores inventory: a sold out type is still purchasable? (availability is checked separately)" do
      limited = create(:ticket_type, capacity: 1)
      hold(limited, status: :paid)

      expect(limited.available_quantity).to eq(0)
      expect(limited).to be_purchasable
    end

    it "ignores hidden and requires_conference_pass" do
      hidden = create(:ticket_type, hidden: true)
      add_on = create(:ticket_type, requires_conference_pass: true)

      expect(hidden).to be_purchasable
      expect(add_on).to be_purchasable
    end
  end

  describe "#conference_pass?" do
    it "matches only slugs prefixed with conference-pass-" do
      expect(create(:ticket_type, slug: "conference-pass-regular")).to be_conference_pass
      expect(create(:ticket_type, slug: "conference-pass-early-bird")).to be_conference_pass
      expect(create(:ticket_type, slug: "explore-pune-day")).not_to be_conference_pass
      expect(create(:ticket_type, slug: "workshop-conference-pass-extra")).not_to be_conference_pass
    end

    it "is independent of the requires_conference_pass flag" do
      add_on = create(:ticket_type, slug: "explore-pune-day", requires_conference_pass: true)

      expect(add_on.requires_conference_pass).to be(true)
      expect(add_on).not_to be_conference_pass
    end
  end

  describe "storefront listing" do
    it "excludes hidden types and orders by position then id" do
      third = create(:ticket_type, position: 2)
      first = create(:ticket_type, position: 0)
      second = create(:ticket_type, position: 0)
      hidden = create(:ticket_type, position: 1, hidden: true)

      listed = described_class.where(hidden: false).order(:position, :id)

      expect(listed.pluck(:id)).to eq([ first.id, second.id, third.id ])
      expect(listed.pluck(:id)).not_to include(hidden.id)
    end

    it "defaults new types to position 0 and visible" do
      expect(ticket_type.position).to eq(0)
      expect(ticket_type.hidden).to be(false)
    end
  end

  describe "inventory enforcement at checkout" do
    let(:order_attributes) { { email: "buyer@example.com", buyer_name: "Buyer" } }

    def checkout(type, quantity: 1)
      Orders::Checkout.call(order_attributes:, items: [ { ticket_type: type, quantity: } ])
    end

    it "sells exactly up to capacity and refuses the next ticket" do
      limited = create(:ticket_type, capacity: 3, max_per_order: 3)

      checkout(limited, quantity: 3)

      expect(limited.available_quantity).to eq(0)
      expect { checkout(limited) }.to raise_error(Orders::Checkout::SoldOut)
      expect(limited.reload.tickets.count).to eq(3)
    end

    it "refuses an order one larger than the remaining stock" do
      limited = create(:ticket_type, capacity: 3, max_per_order: 4)
      checkout(limited, quantity: 1)

      expect { checkout(limited, quantity: 3) }.to raise_error(Orders::Checkout::SoldOut)
      expect { checkout(limited, quantity: 2) }.to change(Order, :count).by(1)
    end

    it "never sells a zero capacity type" do
      expect { checkout(create(:ticket_type, capacity: 0)) }.to raise_error(Orders::Checkout::SoldOut)
    end

    it "does not limit a type with nil capacity" do
      unlimited = create(:ticket_type, capacity: nil, max_per_order: 50)

      expect { checkout(unlimited, quantity: 40) }.to change(Ticket, :count).by(40)
      expect(unlimited.available_quantity).to eq(Float::INFINITY)
    end

    it "resells stock released by an expired hold" do
      limited = create(:ticket_type, capacity: 2, max_per_order: 2)
      order = checkout(limited, quantity: 2)

      expect { checkout(limited) }.to raise_error(Orders::Checkout::SoldOut)

      order.update!(expires_at: 1.second.ago)

      expect { checkout(limited, quantity: 2) }.to change(Order, :count).by(1)
      expect(limited.available_quantity).to eq(0)
    end

    it "refuses to pay an expired order once its stock was resold" do
      limited = create(:ticket_type, capacity: 1)
      first = checkout(limited)
      first.update!(expires_at: 1.second.ago, status: :expired)
      checkout(limited)

      payment_event = create(:payment_event, order: first, amount_paise: first.total_paise)

      expect { first.mark_paid!(payment_event) }.to raise_error(Order::InsufficientAvailability)
      expect(limited.available_quantity).to eq(0)
    end

    it "still pays an expired order when the stock is back" do
      limited = create(:ticket_type, capacity: 1)
      order = checkout(limited)
      order.update!(expires_at: 1.second.ago, status: :expired)
      payment_event = create(:payment_event, order:, amount_paise: order.total_paise)

      expect(order.mark_paid!(payment_event)).to be(true)
      expect(limited.available_quantity).to eq(0)
    end
  end
end
