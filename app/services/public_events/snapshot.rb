module PublicEvents
  class Snapshot
    PER_PAGE = 24

    def self.index(value)
      page = value.is_a?(String) && value.match?(/\A[0-9]{1,9}\z/) ? value.to_i.clamp(1, 1_000) : 1
      events = Event.published.select("events.*, COUNT(*) OVER () AS public_catalog_total").includes(:organization).order(:starts_at, :id).limit(PER_PAGE).offset((page - 1) * PER_PAGE).to_a
      total = events.empty? ? Event.published.count : events.first.read_attribute(:public_catalog_total).to_i
      versioned(schema_version: 1, events: events.map { |event| serialize(event) }, pagination: { page: page, per_page: PER_PAGE, total: total })
    end

    def self.show(event)
      versioned(schema_version: 1, event: serialize(event))
    end

    def self.versioned(payload)
      payload.merge(content_version: Digest::SHA256.hexdigest(JSON.generate(payload)))
    end
    private_class_method :versioned

    def self.serialize(event)
      start_time = event.starts_at.in_time_zone(event.timezone)
      end_time = event.ends_at.in_time_zone(event.timezone)
      {
        id: "hosted-event-#{event.id}", ownership: "hosted_event", title: event.title,
        starts_at: start_time.iso8601(6), ends_at: end_time.iso8601(6),
        start_date: start_time.to_date.iso8601, end_date: end_time.to_date.iso8601,
        timezone: event.timezone,
        organizer: { name: event.organization.name, slug: event.organization.slug },
        details_path: Rails.application.routes.url_helpers.published_event_path(event.organization.slug, event.slug)
      }
    end
    private_class_method :serialize
  end
end
