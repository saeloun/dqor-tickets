require "set"
require "digest"

module Discovery
  class Import
    def self.call(path:, source_key:)
      snapshot = Dataset.read(path, source_key: source_key)
      result = nil
      Source.transaction do
        Source.connection.execute("SELECT pg_advisory_xact_lock(1927110026)")
        source = Source.find_or_create_by!(key: source_key) do |record|
          record.assign_attributes(snapshot.source.except(:key).merge(imported_at: Time.current, last_attempt_at: Time.current))
        end
        source.lock!
        raise Dataset::Invalid, "An older source snapshot cannot replace newer data." if snapshot.source[:fetched_at] < source.fetched_at
        source.update!(snapshot.source.except(:key).merge(imported_at: Time.current, last_attempt_at: Time.current, last_error_code: nil))
        created = 0
        updated = 0
        deduplicated = 0
        seen = Set.new
        snapshot.records.sort_by { |record| record[:external_id] }.each do |record|
          reference = source.references.find_by(external_id: record[:external_id])
          if reference && reference.listing.canonical_url != record[:canonical_url]
            raise Dataset::Invalid, "A source ID changed its canonical event URL; review the mapping first."
          end
          anchor = if record[:canonical_kind] == "collection"
            "#{source.key}:#{record[:occurrence_key]}"
          elsif record[:starts_at]
            record[:starts_at].utc.iso8601
          elsif record[:starts_on]
            record[:starts_on].iso8601
          elsif record[:date_year]
            [ record[:date_year], record[:date_month] ].compact.join("-")
          else
            "#{source.key}:#{record[:external_id]}"
          end
          identity = Digest::SHA256.hexdigest("#{record[:canonical_url]}|#{anchor}")
          listing = reference&.listing || Listing.find_or_initialize_by(identity_key: identity)
          new_listing = listing.new_record?
          if new_listing || listing.primary_source_id == source.id && !seen.include?(listing.id)
            listing.assign_attributes(record.except(:external_id, :source_url).merge(primary_source: source, identity_key: identity))
            listing.save!
            new_listing ? created += 1 : updated += 1
          else
            deduplicated += 1
          end
          seen.add(listing.id)
          reference ||= source.references.new(external_id: record[:external_id])
          reference.update!(listing: listing, source_url: record[:source_url], revision: source.revision, last_seen_at: source.fetched_at)
        end
        result = { source: source.key, revision: source.revision, records: snapshot.records.size, unique_events: seen.size, created: created, updated: updated, deduplicated: deduplicated, missing_records_retained: source.references.where("last_seen_at < ?", source.fetched_at).count }
      end
      result
    rescue Dataset::Invalid
      Source.find_by(key: source_key)&.update!(last_attempt_at: Time.current, last_error_code: "invalid_snapshot")
      raise
    end
  end
end
