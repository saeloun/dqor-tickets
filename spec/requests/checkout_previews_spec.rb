require "rails_helper"

RSpec.describe "Checkout previews", type: :request do
  let(:ticket_type) { create(:ticket_type, price_paise: 400_000) }

  def preview(coupon_code, items: [ { ticket_type_id: ticket_type.id, quantity: 1 } ])
    post checkout_preview_path, params: { checkout_preview: { coupon_code:, items: } }, as: :json
    response.parsed_body.deep_symbolize_keys
  end

  it "quotes a fixed coupon without creating an order or consuming a use" do
    coupon = create(:coupon, code: "FLAT50", ticket_type:, discount_paise: 50_000)

    expect { @quote = preview("flat50") }.not_to change(Order, :count)

    expect(response).to have_http_status(:ok)
    expect(@quote).to eq(
      subtotal_paise: 400_000,
      discount_paise: 50_000,
      total_paise: 350_000,
      coupon: { code: "FLAT50", applied: true, message: nil }
    )
    expect(coupon.reload.uses_count).to eq(0)
  end

  it "quotes a percentage coupon" do
    create(:coupon, code: "TWENTY", ticket_type: nil, discount_paise: nil, percent: 20)

    expect(preview("TWENTY")).to include(discount_paise: 80_000, total_paise: 320_000)
  end

  it "rejects unknown, expired, and maxed coupons with a message" do
    expired = create(:coupon, code: "EXPIRED", ticket_type:, valid_until: 1.minute.ago)
    maxed = create(:coupon, code: "MAXED", ticket_type:, max_uses: 1, uses_count: 1)

    expect(preview("UNKNOWN")[:coupon]).to include(applied: false, message: "Coupon not valid")
    expect(preview(expired.code)[:coupon]).to include(applied: false, message: "Coupon has expired")
    expect(preview(maxed.code)[:coupon]).to include(applied: false, message: "Coupon usage limit reached")
  end

  it "applies a scoped coupon only to its ticket type" do
    other_type = create(:ticket_type, price_paise: 200_000)
    create(:coupon, code: "SCOPED25", ticket_type:, discount_paise: nil, percent: 25)
    items = [
      { ticket_type_id: ticket_type.id, quantity: 1 },
      { ticket_type_id: other_type.id, quantity: 1 }
    ]

    expect(preview("SCOPED25", items:)).to include(
      subtotal_paise: 600_000,
      discount_paise: 100_000,
      total_paise: 500_000
    )
  end

  it "returns the server subtotal for an empty coupon code" do
    expect(preview("")).to eq(
      subtotal_paise: 400_000,
      discount_paise: 0,
      total_paise: 400_000,
      coupon: { code: "", applied: false, message: nil }
    )
  end

  it "matches checkout for the same coupon and items" do
    create(:coupon, code: "MATCH15", ticket_type: nil, discount_paise: nil, percent: 15)
    quote = preview("MATCH15")

    order = Orders::Checkout.call(
      order_attributes: { email: "buyer@example.com", buyer_name: "Buyer" },
      items: [ { ticket_type:, quantity: 1 } ],
      coupon_code: "MATCH15"
    )

    expect(quote[:total_paise]).to eq(order.total_paise)
    expect(quote[:discount_paise]).to eq(order.metadata.fetch("discount_paise"))
  end
end
