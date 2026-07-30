require "rails_helper"

RSpec.describe Organizer, type: :model do
  it "belongs to an account and exposes its tenant records" do
    organizer = create(:organizer)
    event = create(:event, organizer:)
    tax_profile = create(:tax_profile, organizer:)
    sequence = create(:invoice_sequence, organizer:)

    expect(organizer.account).to be_present
    expect(organizer.events).to contain_exactly(event)
    expect(organizer.tax_profiles).to contain_exactly(tax_profile)
    expect(organizer.invoice_sequences).to contain_exactly(sequence)
  end

  it "requires a globally unique normalized slug" do
    create(:organizer, slug: "ruby-india")

    duplicate = build(:organizer, slug: " Ruby-India ")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:slug]).to include("has already been taken")
  end

  it "accepts only direct and route payout modes" do
    expect(build(:organizer, payout_mode: "direct")).to be_valid
    expect(build(:organizer, payout_mode: "route")).to be_valid
    expect(build(:organizer, payout_mode: "manual")).not_to be_valid
  end
end
