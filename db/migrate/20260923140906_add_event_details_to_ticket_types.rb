class AddEventDetailsToTicketTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_types, :event_starts_on, :date
    add_column :ticket_types, :event_ends_on, :date
    add_column :ticket_types, :venue_name, :string
    add_column :ticket_types, :venue_address, :string
  end
end
