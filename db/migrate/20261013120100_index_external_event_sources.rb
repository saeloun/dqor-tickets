class IndexExternalEventSources < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_events_on_organization_and_source_url"

  def up
    execute "SET lock_timeout = '5s'"
    execute "SET statement_timeout = '20s'"
    existing = connection.select_one("SELECT indisvalid FROM pg_index WHERE indexrelid = to_regclass('#{INDEX_NAME}')")
    if existing && !existing["indisvalid"]
      remove_index :events, name: INDEX_NAME, algorithm: :concurrently
    end
    add_index :events, [ :organization_id, :source_url ], unique: true, where: "source_url IS NOT NULL", name: INDEX_NAME, algorithm: :concurrently, if_not_exists: true
  ensure
    execute "RESET lock_timeout"
    execute "RESET statement_timeout"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Keep source deduplication protection when rolling back application code."
  end
end
