class CreateCommunityGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :community_groups do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :tagline
      t.text :description
      t.string :city
      t.string :country_code
      t.string :timezone, null: false, default: "UTC"
      t.string :status, null: false, default: "draft"
      t.timestamps
    end
    add_index :community_groups, [ :organization_id, :slug ], unique: true
    add_index :community_groups, [ :id, :organization_id ], unique: true
    add_check_constraint :community_groups, "status IN ('draft', 'published')", name: "community_group_status"
    add_reference :events, :community_group, index: false
    add_index :events, [ :organization_id, :community_group_id, :starts_at ]
    add_foreign_key :events, :community_groups, column: [ :community_group_id, :organization_id ], primary_key: [ :id, :organization_id ], name: "events_same_organization_group"
  end
end
