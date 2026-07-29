require "rails_helper"

RSpec.describe InvoiceSequence, type: :model do
  it "belongs to an organizer" do
    expect(create(:invoice_sequence).organizer).to be_present
  end

  it "supports every invoice series" do
    expect(described_class.series.keys).to eq(%w[invoice credit_note receipt_voucher commission])
  end

  it "is unique by organizer, series, and fiscal year" do
    sequence = create(:invoice_sequence)
    duplicate = build(:invoice_sequence, organizer: sequence.organizer, series: sequence.series, fiscal_year: sequence.fiscal_year)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:series]).to include("has already been taken")
  end

  it "validates fiscal years and non-negative sequence numbers" do
    sequence = build(:invoice_sequence, fiscal_year: "2026", last_number: -1)

    expect(sequence).not_to be_valid
    expect(sequence.errors).to include(:fiscal_year, :last_number)
  end
end
