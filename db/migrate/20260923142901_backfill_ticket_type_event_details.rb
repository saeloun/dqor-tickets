class BackfillTicketTypeEventDetails < ActiveRecord::Migration[8.1]
  def up
    TicketType.where.not(slug: "rails-girls-pune").update_all(
      event_starts_on: Date.new(2026, 10, 8),
      event_ends_on: Date.new(2026, 10, 11),
      venue_name: "Hyatt Regency Pune",
      venue_address: "Nagar Road, Pune, Maharashtra"
    )

    TicketType.where(slug: "rails-girls-pune").update_all(
      event_starts_on: Date.new(2026, 10, 10),
      event_ends_on: Date.new(2026, 10, 10),
      venue_name: "Zendesk Pune Office",
      venue_address: "ABIL Boulevard, Mundhwa, Pune, Maharashtra"
    )
  end

  def down
    TicketType.update_all(
      event_starts_on: nil,
      event_ends_on: nil,
      venue_name: nil,
      venue_address: nil
    )
  end
end
