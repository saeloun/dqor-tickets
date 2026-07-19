class Avo::Actions::IssueCompTickets < Avo::BaseAction
  self.name = "Issue comp tickets"
  self.standalone = true

  def fields
    field :emails, as: :textarea, name: "Emails, one per line"
    field :attendee_names, as: :textarea, name: "Attendee names, one per line"
  end

  def handle(fields:, **)
    orders = Order.issue_comps!(emails: fields[:emails], attendee_names: fields[:attendee_names])
    succeed "Issued #{orders.size} complimentary tickets"
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    error error.message
    keep_modal_open
  end
end
