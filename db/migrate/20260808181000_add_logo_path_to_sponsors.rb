class AddLogoPathToSponsors < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:sponsors, :logo_path)

    # db:prepare runs in the web entrypoint *before* Puma starts, so a DDL lock
    # that waits forever would hang boot and fail the health check. Bound the
    # wait (SET LOCAL is scoped to this migration's transaction, pooler-safe).
    execute "SET LOCAL lock_timeout = '8s'"
    add_column :sponsors, :logo_path, :string
  end

  def down
    remove_column :sponsors, :logo_path if column_exists?(:sponsors, :logo_path)
  end
end
