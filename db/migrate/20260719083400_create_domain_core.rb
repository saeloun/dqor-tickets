class CreateDomainCore < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_types do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :price_paise, null: false
      t.integer :capacity
      t.datetime :sales_start_at
      t.datetime :sales_end_at
      t.integer :min_per_order, null: false, default: 1
      t.integer :max_per_order
      t.boolean :hidden, null: false, default: false
      t.boolean :requires_conference_pass, null: false, default: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :ticket_types, :slug, unique: true

    create_table :coupons do |t|
      t.string :code, null: false
      t.integer :discount_paise
      t.integer :percent
      t.integer :max_uses
      t.integer :uses_count, null: false, default: 0
      t.references :ticket_type, foreign_key: true
      t.datetime :valid_from
      t.datetime :valid_until
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :coupons, "lower(code)", unique: true, name: :index_coupons_on_lower_code

    create_table :orders do |t|
      t.string :code, null: false
      t.integer :status, null: false, default: 0
      t.string :email, null: false
      t.string :buyer_name, null: false
      t.string :buyer_phone
      t.string :gstin
      t.string :gst_legal_name
      t.string :billing_state_code, limit: 2
      t.integer :total_paise, null: false, default: 0
      t.datetime :expires_at
      t.string :razorpay_order_id
      t.references :coupon, foreign_key: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :orders, :code, unique: true
    add_index :orders, :razorpay_order_id, unique: true

    create_table :admin_users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :admin_users, "lower(email)", unique: true, name: :index_admin_users_on_lower_email

    create_table :sessions do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    create_table :tickets do |t|
      t.references :order, null: false, foreign_key: true
      t.references :ticket_type, null: false, foreign_key: true
      t.integer :price_paise, null: false
      t.string :attendee_name
      t.string :attendee_email
      t.string :tshirt_size
      t.string :dietary_preference
      t.string :secret, null: false
      t.jsonb :checked_in_at, null: false, default: {}
      t.datetime :canceled_at
      t.timestamps
    end
    add_index :tickets, :secret, unique: true

    create_table :payment_events do |t|
      t.string :razorpay_event_id, null: false
      t.string :razorpay_payment_id
      t.references :order, null: false, foreign_key: true
      t.string :kind, null: false
      t.integer :amount_paise, null: false
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end
    add_index :payment_events, :razorpay_event_id, unique: true
    add_index :payment_events, :razorpay_payment_id, unique: true, where: "razorpay_payment_id IS NOT NULL"

    create_table :refunds do |t|
      t.references :order, null: false, foreign_key: true
      t.string :razorpay_refund_id
      t.integer :amount_paise, null: false
      t.string :status, null: false
      t.string :credit_note_number
      t.timestamps
    end

    create_table :invoices do |t|
      t.references :order, null: false, foreign_key: true
      t.string :number, null: false
      t.date :issued_on, null: false
      t.jsonb :buyer_snapshot, null: false, default: {}
      t.jsonb :line_items, null: false, default: []
      t.string :kind, null: false, default: "invoice"
      t.references :refers_to, foreign_key: { to_table: :invoices }
      t.timestamps
    end
    add_index :invoices, :number, unique: true
    add_index :invoices, :order_id, unique: true, where: "kind = 'invoice'", name: :index_invoices_one_invoice_per_order
  end
end
