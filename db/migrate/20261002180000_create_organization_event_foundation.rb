class CreateOrganizationEventFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end
    add_index :organizations, :slug, unique: true

    create_table :memberships do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "viewer"
      t.timestamps
    end
    add_index :memberships, [ :organization_id, :user_id ], unique: true
    add_check_constraint :memberships, "role IN ('owner', 'admin', 'editor', 'viewer')", name: "memberships_valid_role"

    create_table :events do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :timezone, null: false, default: "UTC"
      t.string :status, null: false, default: "draft"
      t.timestamps
    end
    add_index :events, [ :organization_id, :slug ], unique: true
    add_check_constraint :events, "status IN ('draft', 'published')", name: "events_valid_status"
    add_check_constraint :events, "ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at", name: "events_ordered_dates"
    add_check_constraint :events, "status != 'published' OR (starts_at IS NOT NULL AND ends_at IS NOT NULL)", name: "events_publication_dates"
  end
end
