require "json"
require "digest"
require "uri"
require "fileutils"

module Discovery
  class PrepareSnapshots
    def self.call(ruby_path:, react_path:, destination:)
      FileUtils.mkdir_p(destination)
      ruby = JSON.parse(File.read(ruby_path))
      react = JSON.parse(File.read(react_path))
      country_by_timezone = TZInfo::Country.all.each_with_object({}) do |country, result|
        country.zone_identifiers.each { |zone| result[zone] ||= country.code }
      end
      country_by_timezone["Asia/Calcutta"] = "IN"
      ruby_records = ruby.fetch("records").select { |record| %w[event_edition meetup_occurrence].include?(record["record_type"]) }.map do |record|
        date = record["start_date"]
        registration = https_url(record["registration_url"])
        collection = record["record_type"] == "meetup_occurrence"
        location = record["location"].to_s
        row = {
          external_id: record.fetch("id"), source_url: record.fetch("source_url"),
          canonical_url: collection ? record.fetch("canonical_source_url") : (registration || record.fetch("canonical_source_url")),
          canonical_kind: collection ? "collection" : "event",
          occurrence_key: collection ? record.fetch("occurrence_dedup_key") : nil,
          registration_url: registration, title: clean_title(record.fetch("title")), topics: [ "ruby" ],
          city: location.split(",").first.presence, country_code: country_by_timezone[record["timezone"]], timezone: record["timezone"],
          format: record["online"] ? "online" : (record["hybrid"] ? "hybrid" : "unknown"),
          status: record["source_status"] == "cancelled" ? "canceled" : (record["source_status"] == "scheduled" ? "scheduled" : "unknown")
        }
        row.merge!(dates(date, record["end_date"], record["date_precision"]))
        row
      end
      ruby_snapshot = { schema_version: 1, source: { key: "rubyevents", name: "RubyEvents.org", url: ruby.fetch("source_repository"), revision: ruby.fetch("source_revision"), fetched_at: ruby.fetch("source_fetched_at") }, records: ruby_records }
      snapshots = [ [ "rubyevents.json", ruby_snapshot ] ]
      react.fetch("events").group_by { |record| [ URI.parse(record.fetch("original_url")).host, record.fetch("organizer_label") ] }.each do |(host, organizer), events|
        key = "public-#{Digest::SHA256.hexdigest("#{host}|#{organizer}").first(16)}"
        rows = events.map do |record|
          communities = record.fetch("community").map(&:downcase)
          topics = []
          topics << "ruby" if communities.any? { |value| %w[ruby rails].include?(value) }
          topics << "react" if communities.any? { |value| value.include?("react") }
          topics << "javascript" if communities.any? { |value| %w[javascript typescript node.js].include?(value) }
          topics << "developer" if topics.empty?
          row = {
            external_id: record.fetch("dedup_id"), source_url: record.fetch("original_url"), canonical_url: record.fetch("original_url"), canonical_kind: "event",
            registration_url: https_url(record["registration_url"]), title: clean_title(record.fetch("title")), topics: topics,
            city: record["city"], country_code: record["country"], timezone: record["timezone"],
            format: record.fetch("format", "unknown"), status: "unknown", review_state: record["review_required"] ? "hold" : "clear",
            review_reason: record["review_required"] ? "The inspected public sources have missing or conflicting date/time information." : nil
          }
          row.merge!(dates(record["start_date"], record["end_date"], record["date_precision"]))
          if record["occurrence_dates"].present?
            row[:occurrence_dates] = record["occurrence_dates"]
            row[:ends_on] = row[:occurrence_dates].max
          end
          if record["start_time"].present? && row[:starts_on]
            row[:date_precision] = "local_time"
            row[:local_start_time] = record["start_time"]
            row[:local_end_time] = record["end_time"]
            if record["timezone"].present? && record["timezone_status"] == "source_explicit" && !record["review_required"]
              begin
                row[:starts_at] = FreeEvents::Windows.parse_local("#{row[:starts_on]}T#{record['start_time']}", record["timezone"]).utc.iso8601
                row[:ends_at] = FreeEvents::Windows.parse_local("#{row[:ends_on] || row[:starts_on]}T#{record['end_time']}", record["timezone"]).utc.iso8601 if record["end_time"]
                row[:date_precision] = "time"
              rescue FreeEvents::Windows::Invalid
                row[:review_state] = "hold"
                row[:review_reason] = "The published local clock time is ambiguous or nonexistent in its timezone."
              end
            end
          end
          row
        end
        snapshot = { schema_version: 1, source: { key: key, name: clean_title(organizer), url: events.first.fetch("organizer_source_url"), revision: "snapshot-sha256-#{Digest::SHA256.file(react_path).hexdigest}", fetched_at: events.map { |record| record.fetch("observed_at") }.max }, records: rows }
        snapshots << [ "#{key}.json", snapshot ]
      end
      snapshots.each do |name, snapshot|
        Discovery::Dataset.parse(JSON.generate(snapshot), source_key: snapshot[:source][:key])
        File.write(File.join(destination, name), JSON.pretty_generate(snapshot) + "\n")
      end
      { source_snapshots: snapshots.size, ruby_input_records: ruby.fetch("records").size, ruby_event_records: ruby_records.size, ruby_directory_entities_excluded: ruby.fetch("records").size - ruby_records.size, companion_records: react.fetch("events").size, total_event_records: snapshots.sum { |_name, snapshot| snapshot[:records].size }, ruby_revision: ruby.fetch("source_revision") }
    end

    def self.https_url(value)
      value if value.is_a?(String) && value.start_with?("https://")
    end

    def self.clean_title(value)
      value.gsub(/\s+/, " ").strip.truncate(200)
    end

    def self.dates(start_value, end_value, precision)
      case precision
      when "day"
        if start_value && end_value && end_value < start_value
          { date_precision: "date", starts_on: start_value, ends_on: nil, review_state: "hold", review_reason: "The source end date precedes its start date; the conflicting end date is withheld." }
        else
          { date_precision: "date", starts_on: start_value, ends_on: end_value }
        end
      when "month"
        { date_precision: "month", date_year: start_value.split("-").first.to_i, date_month: start_value.split("-")[1].to_i }
      when "year"
        { date_precision: "year", date_year: start_value.to_i }
      else
        { date_precision: "unknown" }
      end
    end
  end
end

puts JSON.generate(Discovery::PrepareSnapshots.call(ruby_path: ARGV.fetch(0), react_path: ARGV.fetch(1), destination: ARGV.fetch(2)))
