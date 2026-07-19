require "rails_helper"

RSpec.describe Gst do
  it "splits GST into CGST and SGST for Maharashtra" do
    expect(described_class.breakdown(350_000, state_code: "27", gstin: "27AAAAA0000A1Z5")).to eq(
      taxable: 296_610,
      cgst: 26_695,
      sgst: 26_695,
      igst: 0
    )
  end

  it "uses IGST for a GST-registered buyer in another state" do
    expect(described_class.breakdown(350_000, state_code: "29", gstin: "29AAAAA0000A1Z5")).to eq(
      taxable: 296_610,
      cgst: 0,
      sgst: 0,
      igst: 53_390
    )
  end

  it "uses Maharashtra CGST and SGST for B2C regardless of state" do
    expect(described_class.breakdown(350_000, state_code: "29")).to eq(
      taxable: 296_610,
      cgst: 26_695,
      sgst: 26_695,
      igst: 0
    )
  end

  it "assigns an odd tax paise remainder to CGST" do
    expect(described_class.breakdown(100, state_code: "27", gstin: "27AAAAA0000A1Z5")).to eq(
      taxable: 85,
      cgst: 8,
      sgst: 7,
      igst: 0
    )
  end
end
