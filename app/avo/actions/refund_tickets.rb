class Avo::Actions::RefundTickets < Avo::BaseAction
  self.name = "Refund selected tickets"

  def fields
    field :ticket_ids, as: :textarea, name: "Ticket IDs"
  end

  def handle(query:, fields:, **)
    return error "Select one order" unless query.one?

    ticket_ids = fields[:ticket_ids].to_s.split(/[\s,]+/).compact_blank
    query.first.refund_tickets!(ticket_ids)
    succeed "Refund initiated"
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    error error.message
    keep_modal_open
  end
end
