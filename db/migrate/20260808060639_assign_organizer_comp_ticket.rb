class AssignOrganizerCompTicket < ActiveRecord::Migration[8.1]
  ORGANIZER_EMAIL = "vipul@saeloun.com".freeze
  ORGANIZER_NAME = "Vipul A M".freeze

  # Issue one complimentary conference ticket to the organiser, with T-shirt
  # size M. Uses the app's own comp flow (Order.issue_comps!) so it gets the
  # invoice + confirmation email like any real comp. Idempotent, and fully
  # rescued so a hiccup here can never fail a deploy.
  def up
    return if organizer_ticket_exists?

    Order.issue_comps!(emails: ORGANIZER_EMAIL, attendee_names: ORGANIZER_NAME).each do |order|
      order.tickets.update_all(tshirt_size: "M")
    end
  rescue => error
    say "Skipped organiser comp ticket: #{error.class}: #{error.message}"
  end

  def down
    # Leave the ticket in place; comp tickets are managed in Avo.
  end

  private
    def organizer_ticket_exists?
      Ticket.where(attendee_email: ORGANIZER_EMAIL)
        .joins(:ticket_type).where(ticket_types: { slug: "complimentary-pass" }).exists?
    end
end
