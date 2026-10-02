module FreeEvents
  class Register
    class Unavailable < StandardError; end

    def self.call(user:, event_id:, ticket_type_id:, registration_answers: {}, form_version_id: nil)
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

        form = FreeEvents::Form.find_by(ticket_type_id: type.id, event_id: event.id)
        version = form&.published_version
        if version
          raise Unavailable, "Registration questions are temporarily unavailable" unless FreeEvents::Questions::Schema.enabled?
          unless form_version_id.to_s == version.id.to_s
            raise FreeEvents::Questions::Invalid, { "form" => "The registration form changed. Review the latest questions and submit again." }
          end
          answers = FreeEvents::Questions::Schema.answers!(version, registration_answers)
        elsif registration_answers.present? || form_version_id.present?
          raise FreeEvents::Questions::Invalid, { "form" => "These questions are not available for this ticket category" }
        end

        order = Order.create!(event_id: event.id, user_id: user.id, email: user.email,
          buyer_name: user.display_name, total_paise: 0, status: :paid)
        ticket = order.tickets.create!(event_id: event.id, ticket_type: type, price_paise: 0,
          attendee_name: user.display_name, attendee_email: user.email, assigned_at: Time.current)
        if version
          FreeEvents::Response.create!(ticket: ticket, form_version: version, event_id: event.id, ticket_type_id: type.id, answers: answers)
        end
        # No legacy comp, provider, invoice, PDF, or email method is called.
        order
      end
    end
  end
end
