require "json"

module Discovery
  class Dataset
    class Invalid < StandardError; end
    MAX_BYTES = 8.megabytes
    MAX_RECORDS = 10_000
    SOURCE_FIELDS = %w[key name url revision fetched_at].freeze
    RECORD_FIELDS = %w[external_id source_url canonical_url canonical_kind occurrence_key registration_url title city country_code format topics status date_precision date_year date_month starts_on ends_on starts_at ends_at timezone local_start_time local_end_time occurrence_dates review_state review_reason].freeze
    Snapshot = Data.define(:source, :records)

    def self.read(path, source_key:)
      raise Invalid, "Snapshot is too large." if File.size(path) > MAX_BYTES
      parse(File.read(path, encoding: "UTF-8"), source_key: source_key)
    rescue JSON::ParserError, EncodingError
      raise Invalid, "Snapshot must contain valid UTF-8 JSON."
    end

    def self.parse(text, source_key:)
      raise Invalid, "Snapshot is too large." if text.bytesize > MAX_BYTES
      input = JSON.parse(text, max_nesting: 20)
      require_fields!(input, %w[schema_version source records])
      raise Invalid, "Unsupported snapshot schema." unless input["schema_version"] == 1
      source = input.fetch("source")
      require_fields!(source, SOURCE_FIELDS)
      raise Invalid, "Source identity does not match." unless source["key"] == source_key && source_key.to_s.match?(/\A[a-z0-9][a-z0-9_-]{0,59}\z/)
      source = { key: source_key, name: string!(source["name"], 120), url: url!(source["url"]), revision: string!(source["revision"], 200), fetched_at: instant!(source["fetched_at"]) }
      raise Invalid, "Fetch timestamp is in the future." if source[:fetched_at] > 5.minutes.from_now
      raw = input.fetch("records")
      raise Invalid, "Records must be a bounded event list." unless raw.is_a?(Array) && raw.size <= MAX_RECORDS
      records = raw.map { |record| record!(record) }
      raise Invalid, "Source record IDs must be unique." unless records.map { |record| record[:external_id] }.uniq.size == records.size
      Snapshot.new(source: source, records: records)
    rescue JSON::ParserError, EncodingError, KeyError, TypeError
      raise Invalid, "Snapshot schema is invalid."
    end

    def self.record!(record)
      require_fields!(record, RECORD_FIELDS, required: %w[external_id source_url canonical_url title topics status date_precision])
      topics = record["topics"]
      raise Invalid, "Topics must identify a supported developer community." unless topics.is_a?(Array) && topics.any? && topics.uniq.size == topics.size && (topics - %w[ruby react javascript developer]).empty?
      precision = record["date_precision"]
      raise Invalid, "Unknown date precision." unless %w[time local_time date month year unknown].include?(precision)
      review = record.fetch("review_state", "clear")
      raise Invalid, "Unknown review state." unless %w[clear hold].include?(review)
      kind = record.fetch("canonical_kind", "event")
      raise Invalid, "Unknown canonical URL kind." unless %w[event collection].include?(kind)
      occurrence_key = record["occurrence_key"] && string!(record["occurrence_key"], 255)
      raise Invalid, "Collection URLs require an occurrence identity." if kind == "collection" && occurrence_key.nil?
      status = record["status"]
      raise Invalid, "Unknown event status." unless %w[scheduled canceled unknown].include?(status)
      format = record.fetch("format", "unknown")
      raise Invalid, "Unknown event format." unless %w[in_person online hybrid unknown].include?(format)
      country = record["country_code"]
      raise Invalid, "Use a two-letter country code." unless country.nil? || country.is_a?(String) && country.match?(/\A[A-Z]{2}\z/)
      timezone = record["timezone"]
      zone = TZInfo::Timezone.get(timezone) if timezone
      dates = { starts_on: date!(record["starts_on"]), ends_on: date!(record["ends_on"]), starts_at: instant!(record["starts_at"], optional: true), ends_at: instant!(record["ends_at"], optional: true), date_year: record["date_year"], date_month: record["date_month"], timezone: timezone }
      if precision == "time"
        raise Invalid, "Exact times require an IANA timezone." unless zone && dates[:starts_at]
        local_date = dates[:starts_at].in_time_zone(timezone).to_date
        raise Invalid, "Local date contradicts the exact time." if dates[:starts_on] && dates[:starts_on] != local_date
        dates[:starts_on] = local_date
        dates[:ends_on] ||= dates[:ends_at]&.in_time_zone(timezone)&.to_date
      elsif %w[date local_time].include?(precision)
        raise Invalid, "A date-only event requires its published date." unless dates[:starts_on]
        raise Invalid, "Date-only records must not invent a time." if dates[:starts_at] || dates[:ends_at]
      else
        raise Invalid, "Uncertain dates must not invent days or times." if dates.values_at(:starts_on, :ends_on, :starts_at, :ends_at).any?
        if %w[month year].include?(precision)
          raise Invalid, "Partial dates require a valid year." unless dates[:date_year].is_a?(Integer) && dates[:date_year].between?(1900, 2200)
        end
        raise Invalid, "Month precision requires a valid month." if precision == "month" && !(dates[:date_month].is_a?(Integer) && dates[:date_month].between?(1, 12))
        raise Invalid, "Year-only records cannot supply a month." if precision == "year" && dates[:date_month]
        raise Invalid, "Unknown dates cannot supply date parts." if precision == "unknown" && (dates[:date_year] || dates[:date_month])
      end
      raise Invalid, "Dates must be ordered." if dates[:ends_on] && (!dates[:starts_on] || dates[:ends_on] < dates[:starts_on])
      raise Invalid, "Times must be ordered." if dates[:ends_at] && (!dates[:starts_at] || dates[:ends_at] < dates[:starts_at])
      times = %w[local_start_time local_end_time].index_with do |field|
        value = record[field]
        raise Invalid, "Local times must use HH:MM without a guessed offset." unless value.nil? || value.is_a?(String) && value.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/)
        value
      end
      raise Invalid, "Local-time precision requires an explicit clock time." if precision == "local_time" && times["local_start_time"].nil?
      raise Invalid, "Uncertain dates cannot supply clock times." if %w[month year unknown].include?(precision) && times.values.any?
      occurrences = record.fetch("occurrence_dates", [])
      raise Invalid, "Occurrence dates must be a bounded list." unless occurrences.is_a?(Array) && occurrences.size <= 31
      occurrences = occurrences.map { |value| date!(value) }
      raise Invalid, "Occurrence dates must be explicit, unique and within the event range." unless occurrences.none?(&:nil?) && occurrences.uniq.size == occurrences.size && occurrences.all? { |date| dates[:starts_on] && date >= dates[:starts_on] && date <= (dates[:ends_on] || dates[:starts_on]) }
      dates.merge(times.transform_keys(&:to_sym)).merge(occurrence_dates: occurrences.sort, review_state: review, review_reason: record["review_reason"] && string!(record["review_reason"], 255), canonical_kind: kind, occurrence_key: occurrence_key, external_id: string!(record["external_id"], 255), source_url: url!(record["source_url"]), canonical_url: url!(record["canonical_url"]), registration_url: record["registration_url"] && url!(record["registration_url"]), title: string!(record["title"], 200), city: record["city"] && string!(record["city"], 120), country_code: country, format: format, topics: topics.sort, status: status, date_precision: precision)
    rescue TZInfo::InvalidTimezoneIdentifier, ArgumentError
      raise Invalid, "Use a valid IANA timezone and date."
    end

    def self.require_fields!(value, allowed, required: allowed)
      raise Invalid, "Only factual event metadata is supported." unless value.is_a?(Hash) && (value.keys - allowed).empty? && (required - value.keys).empty?
    end

    def self.string!(value, limit)
      raise Invalid, "Text metadata is invalid." unless value.is_a?(String) && value.valid_encoding? && value.strip.present? && value.length <= limit && !value.match?(/[\x00-\x1f\x7f]/)
      value.strip
    end

    def self.url!(value)
      CanonicalUrl.call(value)
    rescue CanonicalUrl::Invalid => error
      raise Invalid, error.message
    end

    def self.instant!(value, optional: false)
      return nil if optional && value.nil?
      raise Invalid, "Exact timestamps must include a UTC offset." unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/)
      parts = value.scan(/\d+/).first(6).map(&:to_i)
      raise Invalid, "Exact timestamps must contain a valid date and time." unless Date.valid_date?(*parts.first(3)) && parts[3].between?(0, 23) && parts[4].between?(0, 59) && parts[5].between?(0, 59)
      Time.iso8601(value)
    end

    def self.date!(value)
      return nil if value.nil?
      raise Invalid, "Dates must use YYYY-MM-DD." unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(value)
    end
  end
end
