require "rails_helper"

RSpec.describe PaymentEvent, type: :model do
  it "stamps test mode from the Razorpay key" do
    expect(create(:payment_event).mode).to eq("test")
  end

  it "stamps live mode from the Razorpay key" do
    allow(ENV).to receive(:[]).with("RAZORPAY_KEY_ID").and_return("rzp_live_key")

    expect(create(:payment_event).mode).to eq("live")
  end
end
