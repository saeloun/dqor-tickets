require "rails_helper"

RSpec.describe Payout do
  let(:organizer) { create(:organizer) }

  it "computes net from the settlement waterfall" do
    payout = organizer.payouts.create!(gross_minor: 1_000_000, platform_fee_minor: 50_000, fee_gst_minor: 9_000, tcs_minor: 5_000, tds_minor: 1_000)

    payout.compute_net!

    expect(payout.net_minor).to eq(1_000_000 - 50_000 - 9_000 - 5_000 - 1_000)
  end

  it "tracks payout lines by kind, allowing negative deductions" do
    payout = organizer.payouts.create!(gross_minor: 100)
    sale = payout.payout_lines.create!(kind: "sale", amount_minor: 100)
    tcs = payout.payout_lines.create!(kind: "tcs", amount_minor: -5)

    expect(payout.payout_lines).to include(sale, tcs)
    expect(payout.payout_lines.new(kind: "bogus")).not_to be_valid
  end

  it "has a status lifecycle" do
    payout = organizer.payouts.create!

    expect(payout).to be_pending
    payout.update!(status: "paid")
    expect(payout).to be_paid
  end
end
