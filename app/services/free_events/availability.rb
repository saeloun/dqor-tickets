module FreeEvents
  class Availability
    Result = Data.define(:state, :message, :opens_at, :closes_at, :timezone) do
      def available? = state == :available
    end

    def self.call(event:, ticket_type:, now: Time.current, preview: nil)
      window = preview || RegistrationWindow.find_by(event_id: event.id, ticket_type_id: ticket_type.id)
      configured = preview || window&.published_at
      opens_at = configured && (preview ? window.draft_opens_at : window.opens_at)
      closes_at = configured && (preview ? window.draft_closes_at : window.closes_at)
      closes_at = [ closes_at.presence, event.ends_at ].compact.min
      timezone = configured ? (preview ? window.draft_timezone : window.timezone) : event.timezone
      result = ->(state, message) { Result.new(state: state, message: message, opens_at: opens_at.presence, closes_at: closes_at, timezone: timezone) }
      return result.call(:closed, "Registration is not available for this event.") unless event.published?
      return result.call(:closed, "Registration is not available for this ticket category.") unless ticket_type.event_id == event.id && ticket_type.price_paise.zero? && ticket_type.free_published_at
      return result.call(:closed, "Registration is temporarily unavailable.") if configured && !preview && !Windows.enabled?
      if !Questions::Schema.enabled? && Form.find_by(event_id: event.id, ticket_type_id: ticket_type.id)&.published_version
        return result.call(:closed, "Registration questions are temporarily unavailable.")
      end
      return result.call(:closed, "Registration has closed.") unless closes_at && now < closes_at
      return result.call(:upcoming, "Registration has not opened yet.") if opens_at && now < opens_at
      return result.call(:sold_out, "This event is full.") unless ticket_type.capacity && Ticket.where(event_id: event.id, ticket_type_id: ticket_type.id, canceled_at: nil).count < ticket_type.capacity
      result.call(:available, "Registration is open.")
    end
  end
end
