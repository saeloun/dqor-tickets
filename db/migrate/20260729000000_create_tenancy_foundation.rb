class CreateTenancyFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :billing_email
      t.string :country, limit: 2, null: false, default: "IN"
      t.string :status, null: false, default: "active"
      t.timestamps
    end

    create_table :organizers do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :support_email
      t.string :default_currency, limit: 3, null: false, default: "INR"
      t.string :default_timezone, null: false, default: "Asia/Kolkata"
      t.string :payout_mode, null: false, default: "direct"
      t.string :razorpay_linked_account_id
      t.string :pan
      t.string :entity_type
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :organizers, :slug, unique: true

    create_table :events do |t|
      t.references :organizer, null: false, index: true
      t.string :title, null: false
      t.string :slug, null: false
      t.string :status, null: false, default: "draft"
      t.string :format, null: false, default: "in_person"
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :timezone, null: false, default: "Asia/Kolkata"
      t.string :venue_name
      t.text :venue_address
      t.string :venue_state_code, limit: 2
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string :currency, limit: 3, null: false, default: "INR"
      t.string :visibility, null: false, default: "public"
      t.string :theme
      t.jsonb :brand, null: false, default: {}
      t.boolean :guest_list_public, null: false, default: false
      t.integer :capacity
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :events, [ :organizer_id, :slug ], unique: true

    create_table :tax_profiles do |t|
      t.references :organizer, null: false, index: true
      t.references :event, index: true
      t.string :country, limit: 2, null: false, default: "IN"
      t.string :gstin
      t.string :legal_name, null: false
      t.string :registered_state_code, limit: 2, null: false
      t.text :address, null: false
      t.string :sac_code, null: false, default: "998596"
      t.integer :tax_rate_bp, null: false, default: 1800
      t.boolean :tax_inclusive, null: false, default: true
      t.string :invoice_prefix, null: false
      t.string :cn_prefix, null: false
      t.string :invoice_timing, null: false, default: "immediate"
      t.string :lut_number
      t.timestamps
    end

    create_table :memberships do |t|
      t.references :organizer, null: false, index: true
      t.bigint :user_id, null: false
      t.string :role, null: false
      t.timestamps
    end
    add_index :memberships, [ :organizer_id, :user_id ], unique: true

    create_table :invoice_sequences do |t|
      t.references :organizer, null: false, index: true
      t.string :series, null: false
      t.string :fiscal_year, null: false
      t.integer :last_number, null: false, default: 0
      t.timestamps
    end
    add_index :invoice_sequences, [ :organizer_id, :series, :fiscal_year ], unique: true

    add_foreign_key :organizers, :accounts, validate: false
    add_foreign_key :events, :organizers, validate: false
    add_foreign_key :tax_profiles, :organizers, validate: false
    add_foreign_key :tax_profiles, :events, validate: false
    add_foreign_key :memberships, :organizers, validate: false
    add_foreign_key :invoice_sequences, :organizers, validate: false
  end
end
