require "rails_helper"

RSpec.describe TaxProfile, type: :model do
  it "belongs to an organizer with an optional event override" do
    event = create(:event)
    profile = create(:tax_profile, organizer: event.organizer, event:)

    expect(profile.organizer).to eq(event.organizer)
    expect(profile.event).to eq(event)
  end

  it "accepts a GSTIN with a valid Luhn mod-36 checksum" do
    expect(build(:tax_profile, gstin: "27AAPFU0939F1ZV")).to be_valid
  end

  it "rejects an invalid GSTIN checksum" do
    profile = build(:tax_profile, gstin: "27AAPFU0939F1ZW")

    expect(profile).not_to be_valid
    expect(profile.errors[:gstin]).to include("is invalid")
  end

  it "rejects a malformed GSTIN" do
    expect(build(:tax_profile, gstin: "not-a-gstin")).not_to be_valid
  end

  it "validates tax and invoice settings" do
    profile = build(:tax_profile, registered_state_code: "Maharashtra", tax_rate_bp: 10_001, invoice_timing: "later")

    expect(profile).not_to be_valid
    expect(profile.errors).to include(:registered_state_code, :tax_rate_bp, :invoice_timing)
  end
end
