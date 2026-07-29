class AddTenancyReferences < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :ticket_types, :event_id, :bigint
    add_column :ticket_types, :prerequisite_ticket_type_id, :bigint
    add_column :coupons, :event_id, :bigint
    add_column :orders, :event_id, :bigint
    add_column :orders, :organizer_id, :bigint
    add_column :tickets, :event_id, :bigint
    add_column :invoices, :event_id, :bigint
    add_column :invoices, :organizer_id, :bigint
    add_column :refunds, :event_id, :bigint
    add_column :payment_events, :event_id, :bigint

    add_index :ticket_types, [ :event_id, :slug ], unique: true, name: :index_ticket_types_on_event_id_and_slug
    add_index :ticket_types, :prerequisite_ticket_type_id
    add_index :coupons, [ :event_id, :code ], unique: true
    add_index :orders, [ :event_id, :code ], unique: true, algorithm: :concurrently
    add_index :orders, :organizer_id, algorithm: :concurrently
    add_index :tickets, :event_id, algorithm: :concurrently
    add_index :invoices, :event_id
    add_index :invoices, :organizer_id
    add_index :refunds, :event_id
    add_index :payment_events, :event_id, algorithm: :concurrently

    add_foreign_key :ticket_types, :events, validate: false
    add_foreign_key :ticket_types, :ticket_types, column: :prerequisite_ticket_type_id, validate: false
    add_foreign_key :coupons, :events, validate: false
    add_foreign_key :orders, :events, validate: false
    add_foreign_key :orders, :organizers, validate: false
    add_foreign_key :tickets, :events, validate: false
    add_foreign_key :invoices, :events, validate: false
    add_foreign_key :invoices, :organizers, validate: false
    add_foreign_key :refunds, :events, validate: false
    add_foreign_key :payment_events, :events, validate: false
  end

  def down
    remove_foreign_key :payment_events, :events
    remove_foreign_key :refunds, :events
    remove_foreign_key :invoices, :organizers
    remove_foreign_key :invoices, :events
    remove_foreign_key :tickets, :events
    remove_foreign_key :orders, :organizers
    remove_foreign_key :orders, :events
    remove_foreign_key :coupons, :events
    remove_foreign_key :ticket_types, column: :prerequisite_ticket_type_id
    remove_foreign_key :ticket_types, :events

    remove_index :payment_events, :event_id, algorithm: :concurrently
    remove_index :refunds, :event_id
    remove_index :invoices, :organizer_id
    remove_index :invoices, :event_id
    remove_index :tickets, :event_id, algorithm: :concurrently
    remove_index :orders, :organizer_id, algorithm: :concurrently
    remove_index :orders, name: :index_orders_on_event_id_and_code, algorithm: :concurrently
    remove_index :coupons, [ :event_id, :code ]
    remove_index :ticket_types, :prerequisite_ticket_type_id
    remove_index :ticket_types, name: :index_ticket_types_on_event_id_and_slug

    remove_column :payment_events, :event_id
    remove_column :refunds, :event_id
    remove_column :invoices, :organizer_id
    remove_column :invoices, :event_id
    remove_column :tickets, :event_id
    remove_column :orders, :organizer_id
    remove_column :orders, :event_id
    remove_column :coupons, :event_id
    remove_column :ticket_types, :prerequisite_ticket_type_id
    remove_column :ticket_types, :event_id
  end
end
