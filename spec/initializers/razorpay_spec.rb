require "rails_helper"

RSpec.describe "Razorpay configuration" do
  it "bounds connection and response waits" do
    expect(Razorpay::Request.default_options).to include(open_timeout: 5, read_timeout: 15)
  end
end
