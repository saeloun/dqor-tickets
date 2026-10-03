require "rails_helper"

RSpec.describe "Checkout billing requirements", type: :model do
  let(:ticket_type) { create(:ticket_type, price_paise: 5_000_000, capacity: 10) }
  let(:buyer) { { buyer_name: "Test Buyer", email: "buyer@example.test" } }
  let(:billing) { { billing_address: "Private billing street", billing_state_name: "Maharashtra" } }

  def checkout(attributes = buyer, billing_attributes: {}, coupon_code: nil)
    Orders::Checkout.call(order_attributes: attributes, items: [ { ticket_type_id: ticket_type.id, quantity: 1 } ], billing_attributes:, coupon_code:)
  end

  it "rejects missing high-value billing before inventory or payment effects" do
    expect { checkout }.to raise_error(BillingDetails::Invalid, /Billing address/)
    expect(Order.count).to eq(0)
    expect(Ticket.count).to eq(0)
    expect(PaymentEvent.count).to eq(0)
    order = checkout(buyer.merge(billing_state_code: "27"), billing_attributes: billing)
    expect(order.metadata).to include("billing_address" => "Private billing street", "billing_state_name" => "Maharashtra")
  end

  it "uses the discounted amount for the high-value threshold" do
    create(:coupon, ticket_type:, code: "BELOWLIMIT", discount_paise: 1, percent: nil)
    order = checkout(coupon_code: "BELOWLIMIT")
    expect(order.total_paise).to eq(4_999_999)
    expect(order.metadata["billing_details_requested"]).to be(false)
    expect(order.metadata["discount_paise"]).to eq(1)
  end

  it "requires full registered-buyer facts even below the threshold" do
    ticket_type.update!(price_paise: 100)
    registered = buyer.merge(gstin: "27AAAAA0000A1Z5", gst_legal_name: "Test Buyer Ltd", billing_state_code: "27")
    expect { checkout(registered) }.to raise_error(BillingDetails::Invalid)
    expect(checkout(registered, billing_attributes: billing).metadata["billing_address"]).to eq("Private billing street")
  end

  it "does not require optional details for low-value personal bookings but validates requested particulars" do
    ticket_type.update!(price_paise: 100)
    expect(checkout.total_paise).to eq(100)
    expect { checkout(billing_attributes: { requested: "1" }) }.to raise_error(BillingDetails::Invalid)
  end
end
