class AddStagedCommerceOwnership < ActiveRecord::Migration[8.1]
  def change
    %i[ticket_types orders tickets].each do |table|
      add_reference table, :event, null: true, foreign_key: true
      # NULL identifies legacy DQOR. A generated key makes composite foreign keys
      # enforce legacy/owned separation too (ordinary nullable FKs skip NULLs).
      add_column table, :ownership_key, :virtual, type: :bigint, as: "COALESCE(event_id, 0)", stored: true
      add_check_constraint table, "event_id IS NULL OR event_id > 0", name: "#{table}_positive_event"
    end
    add_index :orders, [ :id, :ownership_key ], unique: true
    add_index :ticket_types, [ :id, :ownership_key ], unique: true
    add_foreign_key :tickets, :orders, column: [ :order_id, :ownership_key ], primary_key: [ :id, :ownership_key ], name: "tickets_order_ownership"
    add_foreign_key :tickets, :ticket_types, column: [ :ticket_type_id, :ownership_key ], primary_key: [ :id, :ownership_key ], name: "tickets_type_ownership"
    # Event-owned inventory cannot appear in, or be sold through, legacy checkout.
    add_check_constraint :ticket_types, "event_id IS NULL OR (hidden = TRUE AND active = FALSE)", name: "event_ticket_types_staged"
  end
end
