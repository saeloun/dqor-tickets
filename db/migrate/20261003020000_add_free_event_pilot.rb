class AddFreeEventPilot < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :free_pilot_identity, :boolean, default: false, null: false
    add_column :ticket_types, :free_published_at, :datetime
    add_check_constraint :ticket_types, "free_published_at IS NULL OR (event_id IS NOT NULL AND price_paise = 0 AND capacity IS NOT NULL AND capacity > 0)", name: "free_inventory_publication"
    add_reference :orders, :user, null: true, foreign_key: true
    add_index :orders, [ :event_id, :user_id ], unique: true, where: "event_id IS NOT NULL", name: "one_free_registration_per_event_user"
    add_check_constraint :orders, "event_id IS NULL OR (user_id IS NOT NULL AND total_paise = 0 AND razorpay_order_id IS NULL AND coupon_id IS NULL)", name: "owned_orders_free_only"
    add_check_constraint :tickets, "event_id IS NULL OR price_paise = 0", name: "owned_tickets_free_only"

    create_table :free_checkins do |t|
      t.references :event, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true, index: { unique: true }
      t.references :operator, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :tickets, [ :id, :ownership_key ], unique: true
    add_foreign_key :free_checkins, :tickets, column: [ :ticket_id, :event_id ], primary_key: [ :id, :ownership_key ], name: "free_checkin_ticket_event"
  end
end
