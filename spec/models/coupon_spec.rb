require "rails_helper"

RSpec.describe Coupon, type: :model do
  let(:regular) { create(:ticket_type, slug: "conference-pass-regular", price_paise: 400_000) }
  let(:order_attributes) { { email: "buyer@example.com", buyer_name: "Buyer" } }

  def checkout(coupon, type: regular)
    Orders::Checkout.call(
      order_attributes:,
      items: [ { ticket_type: type, quantity: 1 } ],
      coupon_code: coupon.code
    )
  end

  it "requires exactly one discount type" do
    expect(build(:coupon, discount_paise: nil, percent: nil)).not_to be_valid
    expect(build(:coupon, discount_paise: 100, percent: 10)).not_to be_valid
    expect(build(:coupon, discount_paise: 100, percent: nil)).to be_valid
  end

  it "rejects inactive coupons" do
    coupon = create(:coupon, ticket_type: regular, active: false)

    expect { checkout(coupon) }.to raise_error(described_class::Invalid, /not active/)
  end

  it "rejects coupons before and after their valid window" do
    future = create(:coupon, ticket_type: regular, valid_from: 1.minute.from_now)
    expired = create(:coupon, ticket_type: regular, valid_until: 1.minute.ago)

    expect { checkout(future) }.to raise_error(described_class::Invalid)
    expect { checkout(expired) }.to raise_error(described_class::Invalid)
  end

  it "rejects a coupon at max uses" do
    coupon = create(:coupon, ticket_type: regular, max_uses: 20, uses_count: 20)

    expect { checkout(coupon) }.to raise_error(described_class::Invalid)
  end

  it "rejects a coupon outside its ticket type scope" do
    coupon = create(:coupon, ticket_type: regular)
    early_bird = create(:ticket_type, slug: "conference-pass-early-bird")

    expect { checkout(coupon, type: early_bird) }.to raise_error(described_class::Invalid, /does not apply/)
  end

  it "snapshots a scoped fixed discount on the order" do
    coupon = create(:coupon, ticket_type: regular, discount_paise: 50_000)

    order = checkout(coupon)

    expect(order.total_paise).to eq(350_000)
    expect(order.metadata).to include("coupon_code" => coupon.code, "discount_paise" => 50_000)
    expect(coupon.reload.uses_count).to eq(0)
  end

  it "increments uses once when payment is confirmed" do
    coupon = create(:coupon, ticket_type: regular, discount_paise: 50_000)
    order = checkout(coupon)
    payment_event = create(:payment_event, order:)

    2.times { order.mark_paid!(payment_event) }

    expect(coupon.reload.uses_count).to eq(1)
    expect(order.invoices.sole.line_items.sole["total_paise"]).to eq(350_000)
  end
end
