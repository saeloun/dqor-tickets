class CreateSponsorship < ActiveRecord::Migration[8.1]
  def change
    create_table :sponsorship_tiers do |t|
      t.references :event, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :level, null: false, default: 0
      t.integer :price_minor
      t.string :currency
      t.integer :max_slots
      t.jsonb :benefits, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :sponsors do |t|
      t.references :event, null: false, foreign_key: true
      t.references :sponsorship_tier, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :website
      t.text :description
      t.string :badge
      t.string :contact_name
      t.string :contact_email
      t.string :entity_type, null: false, default: "other"
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [ :event_id, :slug ], unique: true
    end

    create_table :sponsor_orders do |t|
      t.references :sponsor, null: false, foreign_key: true
      t.references :sponsorship_tier, foreign_key: true
      t.integer :amount_minor, null: false, default: 0
      t.string :currency, null: false, default: "INR"
      t.string :status, null: false, default: "pending"
      t.datetime :signed_at
      t.text :notes
      t.timestamps
    end
  end
end
