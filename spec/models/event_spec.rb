require "rails_helper"

RSpec.describe Event, type: :model do
  it "belongs to an organizer and exposes every scoped record type" do
    event = create(:event)

    expect(event.organizer).to be_present
    expect(%i[tax_profiles ticket_types coupons orders tickets invoices refunds payment_events]).to all(
      satisfy { |association| described_class.reflect_on_association(association).macro == :has_many }
    )
  end

  it "scopes slug uniqueness to the organizer" do
    event = create(:event, slug: "2026")

    expect(build(:event, organizer: event.organizer, slug: "2026")).not_to be_valid
    expect(build(:event, slug: "2026")).to be_valid
  end

  it "defines the planned status and format enums" do
    expect(described_class.statuses.keys).to eq(%w[draft published archived cancelled])
    expect(described_class.formats.keys).to eq(%w[in_person online hybrid])
  end

  it "validates its dates, venue state, and capacity" do
    event = build(:event, starts_at: 2.days.from_now, ends_at: 1.day.from_now, venue_state_code: "MH", capacity: -1)

    expect(event).not_to be_valid
    expect(event.errors).to include(:ends_at, :venue_state_code, :capacity)
  end
end
