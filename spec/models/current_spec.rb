require "rails_helper"

RSpec.describe Current, type: :model do
  it "sets organizer and event only for the tenant block" do
    event = create(:event)

    described_class.with_tenant(organizer: event.organizer, event:) do
      expect(described_class.organizer).to eq(event.organizer)
      expect(described_class.event).to eq(event)
    end

    expect(described_class.organizer).to be_nil
    expect(described_class.event).to be_nil
  end
end
