class CreateAnnouncementDeliveryLedger < ActiveRecord::Migration[8.1]
  def change
    create_table :announcement_preferences do |t|
      t.string :email, null: false
      t.datetime :consented_at
      t.datetime :suppressed_at
      t.string :consent_source
      t.timestamps
    end
    add_index :announcement_preferences, :email, unique: true
    add_check_constraint :announcement_preferences, "email = lower(btrim(email))", name: "announcement_email_normalized"

    create_table :announcement_campaigns do |t|
      t.references :announcement, null: false, foreign_key: true, index: { unique: true }
      t.references :admin_user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :body, null: false
      t.string :content_digest, null: false
      t.integer :audience_count, null: false
      t.datetime :approved_at, null: false
      t.timestamps
    end
    create_table :announcement_deliveries do |t|
      t.references :announcement_campaign, null: false, foreign_key: true
      t.string :email, null: false
      t.string :state, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.string :error_class
      t.datetime :attempted_at
      t.datetime :submitted_at
      t.timestamps
    end
    add_index :announcement_deliveries, [ :announcement_campaign_id, :email ], unique: true, name: "unique_announcement_recipient"
    add_index :announcement_deliveries, [ :state, :id ]
    add_check_constraint :announcement_deliveries, "state IN ('pending','preparing','submitting','submitted','suppressed','failed','unknown')", name: "announcement_delivery_state"
    create_table :announcement_dispatch_limits do |t|
      t.datetime :window_started_at, null: false
      t.integer :used, default: 0, null: false
    end
  end
end
