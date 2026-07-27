class Avo::Actions::RequestAttendeeDetails < Avo::BaseAction
  self.name = "Ask attendee for details"
  self.confirmation = false

  def handle(query:, **)
    assigned, skipped = query.partition(&:assigned?)
    assigned.each(&:request_details!)

    message = "Asked #{assigned.size} #{"attendee".pluralize(assigned.size)} for their details"
    message += " (skipped #{skipped.size} unassigned)" if skipped.any?
    succeed message
  end
end
