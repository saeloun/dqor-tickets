module NativeAttendee
  class ReadSnapshot
    class InvalidCursor < StandardError; end
    PAGE_SIZE = 20
    MAX_CURSOR = 9_223_372_036_854_775_807

    def initialize(user, checked_at: Time.current)
      @user = user
      @checked_at = checked_at
    end

    def envelope
      { schema_version: 1, event: "dqor-2026", checked_at: @checked_at.iso8601 }
    end

    def account
      envelope.merge(account: { id: @user.id.to_s, name: @user.name, email: @user.email })
    end

    def passes(cursor: nil, cursor_supplied: false)
      raise InvalidCursor if cursor_supplied && !valid_cursor?(cursor)

      scope = Ticket.legacy.joins(:order, :ticket_type).merge(Order.legacy).merge(TicketType.legacy)
        .where("lower(btrim(tickets.attendee_email)) = ?", @user.email)
        .where("btrim(tickets.attendee_name) <> ''")
      scope = scope.where("tickets.id > ?", cursor.to_i) if cursor
      tickets = scope.order("tickets.id ASC").limit(PAGE_SIZE + 1).preload(:order, :ticket_type).to_a
      more_results = tickets.size > PAGE_SIZE
      page = tickets.first(PAGE_SIZE)
      envelope.merge(passes: page.map { |ticket| pass_payload(ticket) }, more_results: more_results, next_cursor: more_results ? page.last.id.to_s : nil)
    end

    private
      def valid_cursor?(cursor)
        cursor.is_a?(String) && cursor.length <= 19 && cursor.match?(/\A[1-9][0-9]*\z/) && cursor.to_i <= MAX_CURSOR
      end

      def pass_payload(ticket)
        type = ticket.ticket_type
        status = pass_status(ticket)
        {
          id: ticket.id.to_s,
          type: { id: type.id.to_s, name: type.name },
          status: status,
          admission: { starts_on: type.event_starts_on&.iso8601, ends_on: type.event_ends_on&.iso8601 },
          entry: Ticket::EVENT_DATES.map do |date|
            { date: date.iso8601, eligible: status == "confirmed" && type.valid_on?(date), checked_in_at: ticket.checked_in_at[date.iso8601] }
          end
        }
      end

      def pass_status(ticket)
        order = ticket.order
        return "canceled" if ticket.canceled_at? || order.canceled?
        return "confirmed" if order.paid?
        return "expired" if order.expired? || (order.pending? && order.expires_at && order.expires_at <= @checked_at)

        "pending"
      end
  end
end
