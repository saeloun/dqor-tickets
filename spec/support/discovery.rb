module DiscoverySpecHelpers
  def discovery_record(**changes)
    {
      external_id: "event-one", source_url: "https://example.com/events/one", canonical_url: "https://example.com/events/one",
      title: "Ruby community gathering", city: "Pune", country_code: "IN", topics: [ "ruby" ],
      status: "unknown", date_precision: "date", starts_on: 1.month.from_now.to_date.iso8601, timezone: "Asia/Kolkata"
    }.merge(changes)
  end

  def discovery_snapshot(records: [ discovery_record ], source_key: "demo", revision: "revision-one", fetched_at: Time.current.utc.iso8601)
    { schema_version: 1, source: { key: source_key, name: "Original event source", url: "https://example.com/", revision: revision, fetched_at: fetched_at }, records: records }
  end

  def with_discovery_snapshot(**arguments)
    file = Tempfile.new([ "discovery", ".json" ])
    file.write(JSON.generate(discovery_snapshot(**arguments)))
    file.close
    yield file.path
  ensure
    file&.unlink
  end

  def import_discovery(**arguments)
    key = arguments.fetch(:source_key, "demo")
    with_discovery_snapshot(**arguments) { |path| Discovery::Import.call(path: path, source_key: key) }
  end
end

RSpec.configure { |config| config.include DiscoverySpecHelpers }
