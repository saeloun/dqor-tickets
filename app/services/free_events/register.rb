module FreeEvents
  class Register
    class Unavailable < StandardError; end

    def self.call(user:, event_id:, ticket_type_id:)
      Access.require_enabled!
      raise ActiveRecord::RecordNotFound unless user.is_a?(User) && user.persisted?
      Privacy.enroll!(user)
      Event.transaction do
        event = Event.published.lock.find(event_id)
        # Event lock serializes capacity and one-registration-per-user retries.
        type = TicketType.where(event_id: event.id, price_paise: 0).where.not(free_published_at: nil).find(ticket_type_id)
        existing = Order.find_by(event_id: event.id, user_id: user.id)
        if existing
          raise Unavailable, "Registration is no longer active" unless existing.paid? && existing.tickets.where(canceled_at: nil).exists?
          return existing
        end
        raise Unavailable, "Registration has closed" unless event.ends_at > Time.current
        raise Unavailable, "This event is full" unless type.capacity && Ticket.where(event_id: event.id, ticket_type_id: type.id, canceled_at: nil).count < type.capacity

        order = Order.create!(event_id: event.id, user_id: user.id, email: user.email,
          buyer_name: user.display_name, total_paise: 0, status: :paid)
        order.tickets.create!(event_id: event.id, ticket_type: type, price_paise: 0,
          attendee_name: user.display_name, attendee_email: user.email, assigned_at: Time.current)
        # No legacy comp, provider, invoice, PDF, or email method is called.
        order
      end
    end
  end
end
