module Checkins
  class Record
    def self.call(ticket:, date:, operator:, source:)
      raise ArgumentError, "Check-in operator required" unless operator&.admin? || operator&.desk?

      if ticket.nil?
        CheckinAudit.create!(admin_user: operator, event_date: date, source:, outcome: "not_found")
        return { state: "error", message: "Ticket not found", status: :not_found }
      end

      identity = { ticket_id: ticket.id, attendee: ticket.attendee_name.presence || ticket.attendee_email.presence || "Ticket ##{ticket.id}" }
      begin
        timestamp = ticket.check_in!(date, operator:, source:)
        identity.merge(state: "success", message: "Checked in #{identity[:attendee]}", checked_in_at: timestamp, status: :ok)
      rescue Ticket::AlreadyCheckedIn => error
        CheckinAudit.create!(ticket:, admin_user: operator, event_date: date, source:, outcome: "duplicate")
        time = Time.iso8601(error.checked_in_at).in_time_zone("Asia/Kolkata").strftime("%H:%M")
        identity.merge(state: "warning", message: "Already checked in at #{time}", status: :conflict)
      rescue Ticket::Unconfirmed
        CheckinAudit.create!(ticket:, admin_user: operator, event_date: date, source:, outcome: "unconfirmed")
        identity.merge(state: "error", message: "Order is not confirmed. Do not admit yet.", status: :unprocessable_content)
      rescue Ticket::WrongEventDate
        CheckinAudit.create!(ticket:, admin_user: operator, event_date: date, source:, outcome: "wrong_date")
        identity.merge(state: "error", message: "Ticket is not valid on this event date", status: :unprocessable_content)
      rescue Ticket::Canceled
        CheckinAudit.create!(ticket:, admin_user: operator, event_date: date, source:, outcome: "canceled")
        identity.merge(state: "error", message: "Canceled or refunded ticket", status: :unprocessable_content)
      end
    end
  end
end
