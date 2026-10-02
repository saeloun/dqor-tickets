class CreateEventBrandingSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :event_branding_settings do |t|
      t.string :event_key, null: false, default: "dqor"
      t.jsonb :draft, null: false, default: {}
      t.jsonb :published
      t.jsonb :previous_published
      t.integer :lock_version, null: false, default: 0
      t.references :updated_by, foreign_key: { to_table: :admin_users }
      t.references :published_by, foreign_key: { to_table: :admin_users }
      t.datetime :published_at
      t.timestamps
    end
    add_index :event_branding_settings, :event_key, unique: true
    add_check_constraint :event_branding_settings, "event_key = 'dqor'", name: "event_branding_single_existing_event"

    create_table :event_branding_assets do |t|
      t.references :event_branding_setting, null: false, foreign_key: true
      t.binary :image_data, null: false
      t.string :content_type, null: false
      t.integer :width, null: false
      t.integer :height, null: false
      t.timestamps
    end
  end
end
