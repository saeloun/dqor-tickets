module PublicProgramme
  class Snapshot
    SCHEMA_VERSION = 1
    PUBLIC_ORIGIN = "https://deccanqueenonrails.com".freeze

    def self.call
      new.call
    end

    def call
      speakers = Speaker.publicly_listed.ordered.to_a
      public_speakers = speakers.index_by(&:id)
      payload = {
        schema_version: SCHEMA_VERSION,
        event: {
          id: "dqor-2026", title: "Deccan Queen on Rails 2026",
          start_date: Conference::START_DATE.iso8601, end_date: Conference::END_DATE.iso8601,
          timezone: Conference::ZONE, venue: Conference::VENUE, public_url: PUBLIC_ORIGIN
        },
        sessions: Talk.published.scheduled.map { |talk| session_payload(talk, public_speakers) },
        speakers: speakers.map { |speaker| speaker_payload(speaker) }
      }
      payload.merge(content_version: Digest::SHA256.hexdigest(JSON.generate(payload)))
    end

    private
      def session_payload(talk, speakers)
        speaker = speakers[talk.speaker_id]
        {
          id: talk.id.to_s, title: talk.title, abstract: talk.abstract.presence,
          starts_at: local_time(talk.starts_at), ends_at: local_time(talk.ends_at),
          local_date: talk.starts_at&.in_time_zone(Conference::ZONE)&.to_date&.iso8601,
          speaker_id: speaker&.id&.to_s,
          speaker_name: talk.speaker_id ? speaker&.name : talk.speaker_name.presence,
          room: talk.room.presence
        }
      end

      def speaker_payload(speaker)
        {
          id: speaker.id.to_s, name: speaker.name, title: speaker.title.presence,
          bio: speaker.bio.presence, profile_url: "#{PUBLIC_ORIGIN}/speakers/#{speaker.id}"
        }
      end

      def local_time(time)
        time&.in_time_zone(Conference::ZONE)&.iso8601
      end
  end
end
