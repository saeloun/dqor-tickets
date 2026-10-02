class CreateFreeRegistrationWindows < ActiveRecord::Migration[8.1]
  def change
    create_table :free_registration_windows do |t|
      t.references :event, null: false, foreign_key: true
      t.references :ticket_type, null: false, foreign_key: true, index: { unique: true }
      t.datetime :draft_opens_at
      t.datetime :draft_closes_at
      t.string :draft_timezone, null: false
      t.datetime :opens_at
      t.datetime :closes_at
      t.string :timezone
      t.datetime :published_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_foreign_key :free_registration_windows, :ticket_types, column: [ :ticket_type_id, :event_id ], primary_key: [ :id, :ownership_key ], name: "free_window_type_ownership"
    add_check_constraint :free_registration_windows, "draft_opens_at IS NULL OR draft_closes_at IS NULL OR draft_opens_at < draft_closes_at", name: "free_window_draft_order"
    add_check_constraint :free_registration_windows, "opens_at IS NULL OR closes_at IS NULL OR opens_at < closes_at", name: "free_window_published_order"
  end
end
