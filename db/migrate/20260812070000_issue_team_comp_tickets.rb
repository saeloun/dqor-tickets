class IssueTeamCompTickets < ActiveRecord::Migration[8.1]
  # Free passes for four Saeloun teammates, via the app's own comp flow
  # (Order.issue_comps!) so each gets a real invoice + confirmation email, then
  # a "fill your details" nudge. Idempotent (skips anyone who already has a
  # comp) and fully rescued so a hiccup can never fail a deploy.
  TEAM = {
    "sonam@saeloun.com"   => "Sonam",
    "sana@saeloun.com"    => "Sana",
    "abhaya@saeloun.com"  => "Abhaya",
    "samarth@saeloun.com" => "Samarth"
  }.freeze

  def up
    execute "SET LOCAL lock_timeout = '8s'"

    pending = TEAM.reject { |email, _| comp_exists?(email) }
    return if pending.empty?

    orders = Order.issue_comps!(
      emails: pending.keys.join("\n"),
      attendee_names: pending.values.join("\n")
    )

    orders.flat_map(&:tickets).each do |ticket|
      ticket.request_details!
    rescue => e
      say "Details email skipped for #{ticket.attendee_email}: #{e.message}"
    end
  rescue => e
    say "Skipped team comp tickets: #{e.class} #{e.message}"
  end

  def down
    # Comp tickets are managed in Avo; leave them in place.
  end

  private
    def comp_exists?(email)
      Ticket.where(attendee_email: email)
        .joins(:ticket_type).where(ticket_types: { slug: "complimentary-pass" }).exists?
    end
end
