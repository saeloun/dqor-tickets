require "rails_helper"

RSpec.describe RubyEvents::Exporter do
  let(:event) { create(:event, title: "RubyConf India 2026") }

  it "exports speakers with social handles and a bare github username" do
    event.speakers.create!(name: "Ada Lovelace", github: "@ada", twitter: "ada_t")

    expect(described_class.new(event).speakers)
      .to include(hash_including("name" => "Ada Lovelace", "github" => "ada", "twitter" => "ada_t"))
  end

  it "exports talks as videos with speaker names and track, skipping break slots" do
    track = event.tracks.create!(name: "Main")
    speaker = event.speakers.create!(name: "Grace Hopper")
    talk = event.program_sessions.create!(
      title: "Keynote", kind: "keynote", track:,
      starts_at: Time.utc(2026, 10, 8, 10), ends_at: Time.utc(2026, 10, 8, 11),
      video_provider: "youtube", video_url: "abc123"
    )
    talk.program_session_speakers.create!(speaker:)
    event.program_sessions.create!(title: "Lunch", kind: "break", starts_at: Time.utc(2026, 10, 8, 12), ends_at: Time.utc(2026, 10, 8, 13))

    videos = described_class.new(event).videos

    expect(videos.size).to eq(1)
    expect(videos.first).to include(
      "title" => "Keynote", "speakers" => [ "Grace Hopper" ], "track" => "Main",
      "video_provider" => "youtube", "video_id" => "abc123"
    )
  end

  it "exports sponsors as public metadata only, never pricing" do
    tier = event.sponsorship_tiers.create!(name: "Platinum", level: 1, price_minor: 5_000_000)
    event.sponsors.create!(name: "Acme", website: "https://acme.test", sponsorship_tier: tier, badge: "WiFi Sponsor")

    entry = described_class.new(event).sponsors.first

    expect(entry).to include("name" => "Acme", "tier" => "Platinum", "badge" => "WiFi Sponsor")
    expect(entry.keys).not_to include("price_minor", "amount_minor", "price")
  end

  it "produces the RubyEvents YAML file set" do
    files = described_class.new(event).to_files

    expect(files.keys).to contain_exactly("event.yml", "schedule.yml", "speakers.yml", "videos.yml", "sponsors.yml")
    expect(files["event.yml"]).to include("RubyConf India 2026")
  end
end
