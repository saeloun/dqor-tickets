class AddMultiGatewaySchema < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :orders, :gateway, :string, default: "razorpay", null: false
    add_column :orders, :currency, :string, default: "INR", null: false
    add_column :orders, :gateway_reference, :string
    add_column :orders, :country, :string, default: "IN"

    add_column :payment_events, :gateway, :string, default: "razorpay", null: false
    add_column :payment_events, :gateway_event_id, :string
    add_column :payment_events, :gateway_payment_id, :string

    add_column :refunds, :gateway, :string, default: "razorpay", null: false
    add_column :refunds, :gateway_refund_id, :string

    add_column :ticket_types, :prices_minor, :jsonb, default: {}, null: false

    add_index :orders, [:gateway, :gateway_reference], unique: true, name: :index_orders_on_gateway_and_gateway_reference, algorithm: :concurrently
    add_index :payment_events, [:gateway, :gateway_event_id], unique: true, name: :index_payment_events_on_gateway_and_gateway_event_id, algorithm: :concurrently, where: "gateway_event_id IS NOT NULL"
    add_index :payment_events, [:gateway, :gateway_payment_id], unique: true, name: :index_payment_events_on_gateway_and_gateway_payment_id, algorithm: :concurrently, where: "gateway_payment_id IS NOT NULL"
    add_index :refunds, [:gateway, :gateway_refund_id], unique: true, name: :index_refunds_on_gateway_and_gateway_refund_id, algorithm: :concurrently, where: "gateway_refund_id IS NOT NULL"

    create_table :payments do |t|
      t.references :order, null: false, foreign_key: { validate: false }
      t.string :gateway, null: false
      t.string :gateway_payment_id
      t.string :status, null: false, default: "created"
      t.integer :amount_minor
      t.string :currency
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
  end

  def down
    drop_table :payments

    remove_index :refunds, name: :index_refunds_on_gateway_and_gateway_refund_id, algorithm: :concurrently
    remove_index :payment_events, name: :index_payment_events_on_gateway_and_gateway_payment_id, algorithm: :concurrently
    remove_index :payment_events, name: :index_payment_events_on_gateway_and_gateway_event_id, algorithm: :concurrently
    remove_index :orders, name: :index_orders_on_gateway_and_gateway_reference, algorithm: :concurrently

    remove_column :ticket_types, :prices_minor
    remove_column :refunds, :gateway_refund_id
    remove_column :refunds, :gateway
    remove_column :payment_events, :gateway_payment_id
    remove_column :payment_events, :gateway_event_id
    remove_column :payment_events, :gateway
    remove_column :orders, :country
    remove_column :orders, :gateway_reference
    remove_column :orders, :currency
    remove_column :orders, :gateway
  end
end
