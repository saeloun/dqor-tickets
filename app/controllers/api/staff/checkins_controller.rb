module Api
  module Staff
    class CheckinsController < BaseController
      def resolve
        return unless require_capability("tickets:read")

        ticket = Ticket.legacy.includes(:order, :ticket_type).find_by(secret: params.expect(:secret))
        return render json: { state: "error", message: "Ticket not found" }, status: :not_found unless ticket

        render json: { state: "resolved", date: @date, ticket: ticket_payload(ticket) }
      end

      def index
        return unless require_capability("tickets:read")

        term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip.downcase)}%"
        tickets = Ticket.legacy.confirmed.includes(:order, :ticket_type)
          .where("lower(tickets.attendee_name) LIKE :term OR lower(tickets.attendee_email) LIKE :term OR lower(orders.code) LIKE :term", term:)
          .order(:id).limit(::CheckinsController::SEARCH_LIMIT + 1).to_a
        render json: { date: @date, more_results: tickets.size > ::CheckinsController::SEARCH_LIMIT,
          tickets: tickets.first(::CheckinsController::SEARCH_LIMIT).map { |ticket| ticket_payload(ticket) } }
      end

      def confirm
        return unless require_capability("checkins:write")

        ids = params[:ticket_ids]
        unless params[:confirmed] == true && ids.is_a?(Array) && ids.any? &&
            ids.all? { |id| id.to_s.match?(/\A[1-9]\d*\z/) } && ids.map(&:to_s).uniq.size <= ::CheckinsController::MAX_BATCH_SIZE
          return invalid_request
        end
        results = ids.map(&:to_s).uniq.map do |id|
          Checkins::Record.call(ticket: Ticket.legacy.find_by(id:), date: Date.iso8601(@date), operator: @operator, source: "batch")
            .except(:status).merge(ticket_id: id)
        end
        render json: { date: @date, results: }
      end

      private
        def ticket_payload(ticket)
          eligible = ticket.order.paid? && !ticket.canceled_at? && ticket.ticket_type.valid_on?(Date.iso8601(@date))
          { id: ticket.id, attendee_name: ticket.attendee_name, attendee_email: ticket.attendee_email,
            ticket_type: ticket.ticket_type.name, order_code: ticket.order.code, eligible:,
            checked_in_at: ticket.checked_in_at[@date] }
        end
    end
  end
end
