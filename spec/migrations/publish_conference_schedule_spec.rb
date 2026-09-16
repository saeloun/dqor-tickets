require "rails_helper"
require Rails.root.join("db/migrate/20260916120000_publish_conference_schedule").to_s

RSpec.describe PublishConferenceSchedule do
  it "publishes the latest two-day programme in the event timezone" do
    sam = Speaker.create!(name: "Sam Ruby")

    described_class.new.up

    expect(Talk.published.count).to eq(34)
    expect(Talk.find_by(title: "DHH welcome video")).to be_present
    expect(sam.talks.first.then { [ _1.time_range, _1.day ] }).to eq([ "10:30 AM – 10:50 AM", Date.new(2026, 10, 9) ])
  end
end
