class AddVersionedInvoiceSnapshots < ActiveRecord::Migration[8.1]
  def up
    # Deliberately no defaults/backfill: issued documents must not acquire today's facts.
    add_column :invoices, :snapshot_version, :integer
    add_column :invoices, :seller_snapshot, :json
    add_column :invoices, :tax_snapshot, :json
  end

  def down
    if select_value("SELECT COUNT(*) FROM invoices WHERE snapshot_version IS NOT NULL").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "issued versioned invoice snapshots must be retained"
    end

    remove_column :invoices, :tax_snapshot
    remove_column :invoices, :seller_snapshot
    remove_column :invoices, :snapshot_version
  end
end
