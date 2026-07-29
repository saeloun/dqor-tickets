require "yaml"

module RubyEvents
  # Generates the RubyEvents.org data files (https://github.com/rubyevents/rubyevents)
  # for an event. RubyEvents ingests data as YAML in git (fork + PR), so this
  # produces the file set for a conference edition. Commercial/pricing data is
  # never included -- sponsors export public metadata only.
  class Exporter
    def initialize(event)
      @event = event
    end

    def series
      {
        "name" => @event.organizer.name,
        "slug" => @event.organizer.slug
      }.compact
    end

    def event_metadata
      {
        "name" => @event.title,
        "slug" => @event.slug,
        "start_date" => @event.starts_at&.to_date&.iso8601,
        "end_date" => @event.ends_at&.to_date&.iso8601,
        "location" => @event.venue_name,
        "city" => (@event.brand.is_a?(Hash) ? @event.brand["location"] : nil)
      }.compact
    end

    def schedule
      { "tracks" => @event.tracks.ordered.map { |track| { "name" => track.name, "color" => track.color }.compact } }
    end

    def speakers
      @event.speakers.ordered.map do |speaker|
        {
          "name" => speaker.name,
          "github" => speaker.github,
          "twitter" => speaker.twitter,
          "mastodon" => speaker.mastodon,
          "bluesky" => speaker.bluesky,
          "linkedin" => speaker.linkedin,
          "website" => speaker.website
        }.compact
      end
    end

    def videos
      @event.program_sessions.scheduled.ordered.reject(&:break?).map do |session|
        {
          "title" => session.title,
          "speakers" => session.speakers.ordered.map(&:name),
          "date" => session.starts_at&.to_date&.iso8601,
          "track" => session.track&.name,
          "video_provider" => session.video_provider.presence || "not_recorded",
          "video_id" => session.video_url.presence
        }.compact
      end
    end

    def sponsors
      @event.sponsors.ordered.map do |sponsor|
        {
          "name" => sponsor.name,
          "slug" => sponsor.slug,
          "website" => sponsor.website,
          "tier" => sponsor.sponsorship_tier&.name,
          "badge" => sponsor.badge
        }.compact
      end
    end

    def to_files
      {
        "event.yml" => YAML.dump(event_metadata),
        "schedule.yml" => YAML.dump(schedule),
        "speakers.yml" => YAML.dump(speakers),
        "videos.yml" => YAML.dump(videos),
        "sponsors.yml" => YAML.dump(sponsors)
      }
    end
  end
end
