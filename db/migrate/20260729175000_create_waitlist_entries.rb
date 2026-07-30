class CreateWaitlistEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :waitlist_entries do |t|
      t.references :event, null: false, foreign_key: true
      t.references :ticket_type, foreign_key: true
      t.references :user, foreign_key: true
      t.references :order, foreign_key: true
      t.string :email, null: false
      t.string :name
      t.string :status, null: false, default: "waiting"
      t.string :offer_token
      t.string :cancel_token
      t.datetime :offered_at
      t.datetime :offer_expires_at
      t.integer :position
      t.timestamps
      t.index :offer_token, unique: true
      t.index :cancel_token, unique: true
      t.index [ :event_id, :ticket_type_id, :email ], unique: true, name: "index_waitlist_on_event_type_email"
    end
  end
end
