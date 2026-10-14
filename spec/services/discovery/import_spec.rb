require "rails_helper"

RSpec.describe Discovery::Import do
  it "is idempotent and never creates ownership, RSVP, mail, payment or attendee records" do
    original = [ Organization.count, Membership.count, Event.count, Order.count, Ticket.count, AnnouncementCampaign.count ]
    expect(import_discovery).to include(created: 1, records: 1)
    expect(import_discovery).to include(created: 0, updated: 1)
    expect(Discovery::Listing.count).to eq(1)
    expect(Discovery::Reference.count).to eq(1)
    expect([ Organization.count, Membership.count, Event.count, Order.count, Ticket.count, AnnouncementCampaign.count ]).to eq(original)
    expect(enqueued_jobs).to be_empty
  end

  it "deduplicates the same canonical dated event across sources and retains both provenances" do
    import_discovery
    import_discovery(source_key: "second", records: [ discovery_record(title: "Secondary abbreviated title", canonical_url: "https://example.com/events/one?utm_source=second") ])
    expect(Discovery::Listing.count).to eq(1)
    expect(Discovery::Reference.count).to eq(2)
    expect(Discovery::Listing.first.title).to eq("Ruby community gathering")
  end

  it "keeps distinct editions and recurring nights with a shared parent URL separate" do
    first = discovery_record(canonical_kind: "collection", occurrence_key: "night-one")
    second = first.merge(external_id: "night-two", occurrence_key: "night-two", starts_on: 2.months.from_now.to_date.iso8601)
    import_discovery(records: [ first, second ])
    expect(Discovery::Listing.count).to eq(2)
    import_discovery(records: [ first, second ])
    expect(Discovery::Listing.count).to eq(2)
  end

  it "retains missing records, flags their age and never infers cancellation" do
    import_discovery(fetched_at: 2.hours.ago.utc.iso8601)
    import_discovery(records: [], fetched_at: 1.hour.ago.utc.iso8601, revision: "empty-revision")
    expect(Discovery::Listing.first.status).to eq("unknown")
    expect(Discovery::Reference.first).to be_stale
  end

  it "keeps the last good listing when a later snapshot is invalid" do
    import_discovery
    expect { import_discovery(records: [ discovery_record(title: "") ]) }.to raise_error(Discovery::Dataset::Invalid)
    expect(Discovery::Listing.first.title).to eq("Ruby community gathering")
    expect(Discovery::Source.first.last_error_code).to eq("invalid_snapshot")
  end

  it "rejects older refreshes and source IDs rebound to unrelated canonical URLs" do
    import_discovery
    expect { import_discovery(fetched_at: 1.day.ago.utc.iso8601) }.to raise_error(Discovery::Dataset::Invalid)
    expect { import_discovery(records: [ discovery_record(canonical_url: "https://example.com/unrelated") ]) }.to raise_error(Discovery::Dataset::Invalid)
    expect(Discovery::Listing.count).to eq(1)
  end

  it "requires explicit cancellation evidence and can later recover on an explicit source update" do
    import_discovery
    import_discovery(records: [ discovery_record(status: "canceled") ])
    expect(Discovery::Listing.first).to be_status_canceled
    import_discovery(records: [ discovery_record(status: "scheduled") ])
    expect(Discovery::Listing.first).to be_status_scheduled
  end
  it "keeps separate timed occurrences on the same canonical page and day distinct" do
    records = [
      discovery_record(external_id: "morning", date_precision: "time", starts_on: "2026-11-01", starts_at: "2026-11-01T09:00:00+05:30"),
      discovery_record(external_id: "evening", date_precision: "time", starts_on: "2026-11-01", starts_at: "2026-11-01T18:00:00+05:30")
    ]
    import_discovery(records: records)
    expect(Discovery::Listing.count).to eq(2)
    expect(import_discovery(records: records)).to include(created: 0, updated: 2)
    expect(Discovery::Listing.count).to eq(2)
  end
end
