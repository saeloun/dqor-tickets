module FreeEvents
  class CheckIn
    def self.call(user:, organization_id:, event_id:, ticket_id:)
      Access.with_manager(user: user, organization_id: organization_id, event_id: event_id) do |event|
        raise ArgumentError, "Check-in is open only during the event" unless event.published? && Time.current.between?(event.starts_at, event.ends_at)
        ticket = Ticket.joins(:order, :ticket_type).where(event_id: event.id, canceled_at: nil)
          .where(orders: { event_id: event.id, status: Order.statuses[:paid] }, ticket_types: { event_id: event.id }).find(ticket_id)
        FreeCheckin.find_or_create_by!(ticket: ticket) { |entry| entry.event = event; entry.operator = user }
      end
    end
  end
end
