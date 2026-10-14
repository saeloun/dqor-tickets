class CreateEventDiscovery < ActiveRecord::Migration[8.1]
  def change
    create_table :discovery_sources do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :url, limit: 2_000, null: false
      t.string :revision, null: false
      t.datetime :fetched_at, null: false
      t.datetime :imported_at, null: false
      t.datetime :last_attempt_at, null: false
      t.string :last_error_code
      t.timestamps
    end
    add_index :discovery_sources, :key, unique: true

    create_table :discovery_listings do |t|
      t.references :primary_source, null: false, foreign_key: { to_table: :discovery_sources }
      t.string :identity_key, null: false
      t.string :canonical_kind, null: false, default: "event"
      t.string :occurrence_key
      t.string :canonical_url, limit: 2_000, null: false
      t.string :registration_url, limit: 2_000
      t.string :title, null: false
      t.string :city
      t.string :country_code
      t.string :format, null: false, default: "unknown"
      t.string :topics, array: true, null: false, default: []
      t.string :status, null: false, default: "unknown"
      t.string :date_precision, null: false, default: "unknown"
      t.string :review_state, null: false, default: "clear"
      t.string :review_reason
      t.string :local_start_time
      t.string :local_end_time
      t.date :occurrence_dates, array: true, null: false, default: []
      t.integer :date_year
      t.integer :date_month
      t.date :starts_on
      t.date :ends_on
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :timezone
      t.timestamps
    end
    add_index :discovery_listings, :identity_key, unique: true
    add_index :discovery_listings, :canonical_url
    add_index :discovery_listings, :topics, using: :gin
    add_index :discovery_listings, [ :country_code, :starts_on ]
    add_index :discovery_listings, :starts_at
    add_check_constraint :discovery_listings, "status IN ('scheduled', 'canceled', 'unknown')", name: "discovery_valid_status"
    add_check_constraint :discovery_listings, "date_precision IN ('time', 'local_time', 'date', 'month', 'year', 'unknown')", name: "discovery_valid_precision"
    add_check_constraint :discovery_listings, "format IN ('in_person', 'online', 'hybrid', 'unknown')", name: "discovery_valid_format"
    add_check_constraint :discovery_listings, "ends_on IS NULL OR starts_on IS NOT NULL AND ends_on >= starts_on", name: "discovery_ordered_dates"
    add_check_constraint :discovery_listings, "ends_at IS NULL OR starts_at IS NOT NULL AND ends_at >= starts_at", name: "discovery_ordered_times"
    add_check_constraint :discovery_listings, "date_precision <> 'time' OR starts_at IS NOT NULL AND starts_on IS NOT NULL AND timezone IS NOT NULL", name: "discovery_time_precision"
    add_check_constraint :discovery_listings, "date_precision <> 'date' OR starts_on IS NOT NULL", name: "discovery_date_precision"

    add_check_constraint :discovery_listings, "review_state IN ('clear', 'hold')", name: "discovery_valid_review"
    add_check_constraint :discovery_listings, "canonical_kind IN ('event', 'collection') AND (canonical_kind <> 'collection' OR occurrence_key IS NOT NULL)", name: "discovery_occurrence_identity"

    create_table :discovery_references do |t|
      t.references :source, null: false, foreign_key: { to_table: :discovery_sources }
      t.references :listing, null: false, foreign_key: { to_table: :discovery_listings }
      t.string :external_id, null: false
      t.string :source_url, limit: 2_000, null: false
      t.string :revision, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :discovery_references, [ :source_id, :external_id ], unique: true
  end
end
