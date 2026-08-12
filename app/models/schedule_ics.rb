class ScheduleIcs
  PRODID = "-//Deccan Queen on Rails//Personal Schedule//EN".freeze
  CAL_NAME = "My Deccan Queen on Rails schedule".freeze
  DEFAULT_LOCATION = "Hyatt Regency, Pune".freeze
  DEFAULT_DURATION = 30.minutes

  def initialize(talks)
    @talks = talks
  end

  def to_ics
    lines = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:#{PRODID}",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "X-WR-CALNAME:#{escape(CAL_NAME)}"
    ]
    @talks.each { |talk| lines.concat(vevent(talk)) }
    lines << "END:VCALENDAR"
    lines.join("\n")
  end

  private
    def vevent(talk)
      finish = talk.ends_at || (talk.starts_at + DEFAULT_DURATION)
      [
        "BEGIN:VEVENT",
        "UID:talk-#{talk.id}@deccanqueenonrails.com",
        "DTSTAMP:#{utc(Time.current)}",
        "DTSTART:#{utc(talk.starts_at)}",
        "DTEND:#{utc(finish)}",
        "SUMMARY:#{escape(talk.title)}",
        "LOCATION:#{escape(talk.room.presence || DEFAULT_LOCATION)}",
        "DESCRIPTION:#{escape(description(talk))}",
        "END:VEVENT"
      ]
    end

    def description(talk)
      parts = []
      parts << "Speaker: #{talk.speaker_display}" if talk.speaker_display.present?
      parts << "Track: #{talk.track}" if talk.track.present?
      parts << "https://deccanqueenonrails.com/schedule"
      parts.join("\n")
    end

    def utc(time)
      time.utc.strftime("%Y%m%dT%H%M%SZ")
    end

    # RFC 5545 text escaping: backslash, semicolon, comma, and newlines.
    def escape(text)
      text.to_s.gsub(/([\\;,\n])/) { |char| char == "\n" ? "\\n" : "\\#{char}" }
    end
end
