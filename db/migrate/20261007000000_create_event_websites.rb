class CreateEventWebsites < ActiveRecord::Migration[8.1]
  def change
    create_table :event_website_settings do |t|
      t.references :event, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :draft, null: false
      t.jsonb :published
      t.jsonb :previous_published
      t.integer :lock_version, null: false, default: 0
      t.references :updated_by, foreign_key: { to_table: :users }
      t.references :published_by, foreign_key: { to_table: :users }
      t.datetime :published_at
      t.timestamps
    end
    add_check_constraint :event_website_settings, "jsonb_typeof(draft) = 'object'", name: "event_website_draft_object"
    add_check_constraint :event_website_settings, "published IS NULL OR jsonb_typeof(published) = 'object'", name: "event_website_published_object"
    add_check_constraint :event_website_settings, "previous_published IS NULL OR jsonb_typeof(previous_published) = 'object'", name: "event_website_previous_object"

    create_table :event_website_assets do |t|
      t.references :event_website_setting, null: false, foreign_key: true
      t.binary :image_data, null: false
      t.string :content_type, null: false
      t.integer :width, null: false
      t.integer :height, null: false
      t.timestamps
    end
    add_check_constraint :event_website_assets, "content_type = 'image/webp' AND octet_length(image_data) BETWEEN 1 AND 1048576 AND width BETWEEN 1 AND 4096 AND height BETWEEN 1 AND 4096 AND width::bigint * height <= 12000000", name: "event_website_bounded_raster"
  end
end
