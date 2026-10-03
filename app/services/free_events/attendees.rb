require "csv"

module FreeEvents
  class Attendees
    FIELDS = %w[id attendee_name attendee_email checked_in_at].freeze

    def self.rows(user:, organization_id:, event_id:)
      Access.with_manager(user: user, organization_id: organization_id, event_id: event_id) do |event|
        checkins = FreeCheckin.where(event_id: event.id).pluck(:ticket_id, :created_at).to_h
        Ticket.joins(:order).where(event_id: event.id, canceled_at: nil)
          .where(orders: { event_id: event.id, status: Order.statuses[:paid] }).order(:id).map do |ticket|
            { "id" => ticket.id, "attendee_name" => ticket.attendee_name,
              "attendee_email" => ticket.attendee_email, "checked_in_at" => checkins[ticket.id] }
          end
      end
    end

    def self.csv(**arguments)
      CSV.generate do |csv|
        csv << FIELDS
        rows(**arguments).each do |row|
          csv << FIELDS.map do |field|
            value = row[field]
            value.is_a?(String) && value.match?(/\A\s*[=+@-]/) ? "'#{value}" : value
          end
        end
      end
    end
  end
end
