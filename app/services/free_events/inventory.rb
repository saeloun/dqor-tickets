module FreeEvents
  class Inventory
    def self.publish!(user:, organization_id:, event_id:, name:, capacity:)
      Access.with_manager(user: user, organization_id: organization_id, event_id: event_id) do |event|
        raise ArgumentError, "Publish event dates first" unless event.published? && event.ends_at > Time.current
        limit = Integer(capacity, exception: false)
        raise ArgumentError, "Capacity must be between 1 and 10000" unless limit && (1..10000).cover?(limit)
        raise ArgumentError, "Name is required" if name.to_s.strip.empty? || name.to_s.length > 120
        raise ArgumentError, "This pilot supports one free ticket type per event" if TicketType.where(event_id: event.id).where.not(free_published_at: nil).exists?
        TicketType.create!(event_id: event.id, name: name.to_s.strip, capacity: limit,
          slug: "free-#{event.id}-#{SecureRandom.hex(12)}", price_paise: 0, hidden: true, active: false,
          min_per_order: 1, max_per_order: 1, free_published_at: Time.current)
      end
    end
  end
end
