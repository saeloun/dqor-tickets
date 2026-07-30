class CreateRegistrations < ActiveRecord::Migration[8.1]
  def change
    create_table :registrations do |t|
      t.bigint :event_id, null: false
      t.bigint :user_id, null: false
      t.bigint :ticket_id
      t.string :attendance_state, null: false, default: "interested"
      t.string :payment_state, null: false, default: "not_required"
      t.string :source, null: false, default: "self"
      t.timestamps
    end
    add_index :registrations, [ :event_id, :user_id ], unique: true
    add_index :registrations, :user_id
    add_index :registrations, :ticket_id
    add_foreign_key :registrations, :events, validate: false
    add_foreign_key :registrations, :users, validate: false
    add_foreign_key :registrations, :tickets, validate: false
  end
end
