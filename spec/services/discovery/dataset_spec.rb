require "rails_helper"

RSpec.describe Discovery::Dataset do
  def parse(record = discovery_record)
    described_class.parse(JSON.generate(discovery_snapshot(records: [ record ])), source_key: "demo")
  end

  it "retains source identity, unknown status and date-only timezone precision" do
    result = parse
    expect(result.source).to include(key: "demo", revision: "revision-one")
    expect(result.records.first).to include(status: "unknown", date_precision: "date", timezone: "Asia/Kolkata", starts_at: nil)
  end

  it "rejects attendee, ownership and copied-content fields instead of ingesting them" do
    %i[attendees organization_id description image_url].each do |field|
      expect { parse(discovery_record.merge(field => "private")) }.to raise_error(described_class::Invalid)
    end
  end

  it "rejects unsafe, local and credential-bearing URLs" do
    %w[javascript:alert(1) http://example.com/ https://127.0.0.1/ https://events.local/ https://example.com/?token=private].each do |url|
      expect { parse(discovery_record(canonical_url: url)) }.to raise_error(described_class::Invalid)
    end
  end

  it "canonically removes tracking and fragments without changing event identity" do
    result = parse(discovery_record(canonical_url: "https://EXAMPLE.com/events/one?utm_source=test&day=2#details"))
    expect(result.records.first[:canonical_url]).to eq("https://example.com/events/one?day=2")
  end

  it "does not invent a day or UTC midnight for uncertain source dates" do
    record = discovery_record(date_precision: "year", starts_on: nil, timezone: nil, date_year: 2027)
    expect(parse(record).records.first).to include(date_year: 2027, starts_on: nil, starts_at: nil)
    expect { parse(record.merge(starts_on: "2027-01-01")) }.to raise_error(described_class::Invalid)
  end

  it "requires genuine timezone and calendar values for exact timestamps" do
    record = discovery_record(date_precision: "time", starts_on: nil, starts_at: "2027-02-30T12:00:00Z", timezone: "UTC")
    expect { parse(record) }.to raise_error(described_class::Invalid)
    expect { parse(record.merge(starts_at: "2027-02-20T12:00:00Z", timezone: nil)) }.to raise_error(described_class::Invalid)
    expect { parse(record.merge(starts_at: "2027-02-20T12:00:00Z", timezone: "Private/Guess")) }.to raise_error(described_class::Invalid)
  end

  it "preserves an explicit clock time with unknown timezone without manufacturing UTC" do
    record = discovery_record(date_precision: "local_time", local_start_time: "18:30", timezone: nil)
    expect(parse(record).records.first).to include(local_start_time: "18:30", timezone: nil, starts_at: nil)
  end

  it "requires occurrence identity for recurring parent URLs" do
    expect { parse(discovery_record(canonical_kind: "collection")) }.to raise_error(described_class::Invalid)
  end

  it "validates all bundled factual snapshots and excludes groups and talks" do
    snapshots = Dir[Rails.root.join("db/discovery_snapshots/*.json")].map do |path|
      data = JSON.parse(File.read(path))
      described_class.read(path, source_key: data.fetch("source").fetch("key"))
    end
    expect(snapshots.sum { |snapshot| snapshot.records.size }).to eq(2_121)
    ruby = snapshots.find { |snapshot| snapshot.source[:key] == "rubyevents" }
    expect(ruby.records.size).to eq(2_061)
    expect(ruby.records.none? { |record| record[:external_id].include?("meetup_group:") || record[:external_id].include?(":series:") }).to be(true)
    expect(ruby.records.count { |record| record[:status] == "canceled" }).to eq(13)
  end
end
