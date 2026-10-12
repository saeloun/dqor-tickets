require "rails_helper"

RSpec.describe "Published owned event timestamp precision", type: :request do
  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:public_events_enabled).and_return(true)
  end

  it "preserves durable microseconds through real detail and catalog serializer output" do
    organization = Organization.create!(name: "Synthetic precision organizers", slug: "synthetic-precision-organizers")
    start_time = Time.utc(2026, 11, 6, 18, 45)
    event = organization.events.create!(id: 9_000_000_000_000_001, title: "Synthetic timestamp precision", slug: "synthetic-precision", status: :published, timezone: "Asia/Kolkata", starts_at: start_time, ends_at: start_time + 1)

    [ [ 100_000, 900_000, "subsecond" ], [ 1, 2, "microsecond" ] ].each do |first, last, fixture|
      event.update!(starts_at: start_time + Rational(first, 1_000_000), ends_at: start_time + Rational(last, 1_000_000))
      event.reload
      expect(event.ends_at).to be > event.starts_at
      get public_event_path("hosted-event-#{event.id}")
      expect(response).to have_http_status(:ok)
      row = response.parsed_body.fetch("event")
      expect(row.fetch("starts_at")).to eq(event.starts_at.in_time_zone(event.timezone).iso8601(6))
      expect(row.fetch("ends_at")).to eq(event.ends_at.in_time_zone(event.timezone).iso8601(6))
      expect(Time.iso8601(row.fetch("ends_at"))).to be > Time.iso8601(row.fetch("starts_at"))
      expected = JSON.parse(Rails.root.join("docs/contracts/public_owned_events_v1.#{fixture}.example.json").read)
      expect(response.parsed_body).to eq(expected)
      expect(response.headers["Set-Cookie"]).to be_nil
      get public_events_path
      expected_catalog = JSON.parse(Rails.root.join("docs/contracts/public_owned_events_v1.#{fixture}.catalog.example.json").read)
      expect(response.parsed_body).to eq(expected_catalog)
      expect(response.parsed_body.fetch("events")).to eq([ row ])
      expect(response.headers["Set-Cookie"]).to be_nil
    end
  end
end
