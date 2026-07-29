class CreateMediaAndDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :media_items do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :kind, null: false, default: "image"
      t.string :source, null: false, default: "upload"
      t.string :external_url
      t.string :external_ref
      t.text :caption
      t.string :attribution
      t.string :moderation_state, null: false, default: "pending"
      t.boolean :consent_given, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :gallery_sources do |t|
      t.references :event, null: false, foreign_key: true
      t.string :provider, null: false, default: "instagram"
      t.string :query, null: false
      t.jsonb :config, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.datetime :last_synced_at
      t.timestamps
    end

    create_table :video_assets do |t|
      t.references :program_session, null: false, foreign_key: true
      t.string :youtube_id
      t.string :status, null: false, default: "pending"
      t.string :title
      t.datetime :published_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    create_table :push_devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :token, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_seen_at
      t.timestamps
      t.index [ :platform, :token ], unique: true
    end
  end
end
