require "rails_helper"

RSpec.describe ExistingDqorEvent do
  it "resolves only an explicitly configured published event when enabled" do
    organization = Organization.create!(name: "DQOR", slug: "dqor")
    event = organization.events.create!(title: "DQOR", slug: "dqor")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DQOR_PLATFORM_EVENT_ID").and_return(event.id.to_s)
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(false)
    expect(described_class.resolve).to be_nil
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    expect(described_class.resolve).to be_nil
    event.update!(status: :published, starts_at: Time.current, ends_at: 1.hour.from_now)
    expect(described_class.resolve).to eq(event)
    allow(ENV).to receive(:[]).with("DQOR_PLATFORM_EVENT_ID").and_return(nil)
    expect(described_class.resolve).to be_nil
  end
end
