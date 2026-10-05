class CreateEventSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :event_slots do |t|
      t.string :name, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.boolean :active, null: false, default: false
      t.integer :capacity
      t.integer :redemption_limit, null: false, default: 1
      t.bigint :ticket_type_ids, array: true, null: false, default: []
      t.timestamps
    end
    create_table :event_slot_redemptions do |t|
      t.references :event_slot, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :request_key, null: false
      t.datetime :redeemed_at, null: false
      t.datetime :voided_at
      t.bigint :voided_by_id
      t.string :void_reason
      t.timestamps
    end
    add_foreign_key :event_slot_redemptions, :admin_users, column: :voided_by_id
    add_index :event_slot_redemptions, [ :event_slot_id, :request_key ], unique: true
    add_check_constraint :event_slots, 'ends_at > starts_at AND redemption_limit > 0 AND (capacity IS NULL OR capacity > 0)', name: 'event_slot_limits'
  end
end
