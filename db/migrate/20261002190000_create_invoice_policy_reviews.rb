class CreateInvoicePolicyReviews < ActiveRecord::Migration[8.1]
  def up
    create_table :invoice_policy_reviews do |t|
      t.jsonb :policy_data, null: false, default: {}
      t.string :status, null: false, default: "draft"
      t.references :created_by, null: false, foreign_key: { to_table: :admin_users }
      t.references :approved_by, foreign_key: { to_table: :admin_users }
      t.references :supersedes, foreign_key: { to_table: :invoice_policy_reviews }
      t.datetime :configured_at
      t.datetime :approved_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
  end

  def down
    if select_value("SELECT COUNT(*) FROM invoice_policy_reviews WHERE status = 'approved'").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "approved finance review records must be retained"
    end
    drop_table :invoice_policy_reviews
  end
end
