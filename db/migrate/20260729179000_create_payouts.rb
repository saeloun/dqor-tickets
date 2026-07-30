class CreatePayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :payouts do |t|
      t.references :organizer, null: false, foreign_key: true
      t.references :event, foreign_key: true
      t.date :period_start
      t.date :period_end
      t.integer :gross_minor, null: false, default: 0
      t.integer :platform_fee_minor, null: false, default: 0
      t.integer :fee_gst_minor, null: false, default: 0
      t.integer :tcs_minor, null: false, default: 0
      t.integer :tds_minor, null: false, default: 0
      t.integer :net_minor, null: false, default: 0
      t.string :currency, null: false, default: "INR"
      t.string :status, null: false, default: "pending"
      t.jsonb :route_transfer_ids, null: false, default: []
      t.string :provider_payout_ref
      t.timestamps
    end

    create_table :payout_lines do |t|
      t.references :payout, null: false, foreign_key: true
      t.references :order, foreign_key: true
      t.string :kind, null: false, default: "sale"
      t.integer :amount_minor, null: false, default: 0
      t.timestamps
    end
  end
end
