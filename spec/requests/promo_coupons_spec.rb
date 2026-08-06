require "rails_helper"

# Guards the money math for the two live coupon shapes:
#   * the shared 10% organiser/referral code (DQOR10, created by migration), and
#   * a 100%-off sponsor code with a capped number of uses (Zendesk-style;
#     the real code lives only in prod/Avo, never in this public repo).
RSpec.describe "Promo & sponsor coupons", type: :request do
  let(:ticket_type) { create(:ticket_type, slug: "conference-pass-regular", price_paise: 550_000, capacity: 100, max_per_order: 4) }
  let(:razorpay_url) { "https://api.razorpay.com/v1/orders" }

  def preview(coupon_code, quantity: 1)
    post checkout_preview_path,
      params: { checkout_preview: { coupon_code:, items: [ { ticket_type_id: ticket_type.id, quantity: } ] } },
      as: :json
    JSON.parse(response.body).deep_symbolize_keys
  end

  describe "the shared 10% organiser code (DQOR10 shape)" do
    it "takes 10% off any pass, across the whole order" do
      create(:coupon, code: "DQOR10", ticket_type: nil, discount_paise: nil, percent: 10, max_uses: 30)

      result = preview("DQOR10", quantity: 2) # 2 x 5500 = 11000.00

      expect(result[:discount_paise]).to eq(110_000)
      expect(result[:total_paise]).to eq(990_000)
      expect(result[:coupon]).to include(applied: true)
    end

    it "stops applying once its redemption cap is spent" do
      create(:coupon, code: "DQOR10", ticket_type: nil, discount_paise: nil, percent: 10, max_uses: 30, uses_count: 30)

      expect(preview("DQOR10")[:coupon]).to include(applied: false, message: "Coupon usage limit reached")
    end
  end

  describe "a 100%-off sponsor code (free tickets, capped uses)" do
    it "makes the order free without calling Razorpay and consumes one use" do
      allow(PdfRenderer).to receive(:render)
      coupon = create(:coupon, code: "SPONSORFREE", ticket_type: nil, discount_paise: nil, percent: 100, max_uses: 5)

      post orders_path, params: {
        checkout: {
          email: "sponsor@example.com", buyer_name: "Sponsor", buyer_phone: "9999999999",
          coupon_code: "SPONSORFREE", quantities: { ticket_type.id.to_s => "1" }
        }
      }

      order = Order.last
      expect(order).to be_paid
      expect(order.total_paise).to eq(0)
      expect(order.payment_events.sole.kind).to eq("comp")
      expect(coupon.reload.uses_count).to eq(1)
      expect(a_request(:post, razorpay_url)).not_to have_been_made
    end

    it "is refused after the cap is spent" do
      create(:coupon, code: "SPONSORFREE", ticket_type: nil, discount_paise: nil, percent: 100, max_uses: 5, uses_count: 5)

      expect(preview("SPONSORFREE")[:coupon]).to include(applied: false, message: "Coupon usage limit reached")
    end
  end
end
