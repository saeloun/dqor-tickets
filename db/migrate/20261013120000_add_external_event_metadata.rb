class AddExternalEventMetadata < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    execute "SET LOCAL statement_timeout = '20s'"
    %i[description venue_name venue_address source_url external_registration_url cfp_url topics import_notes].each do |name|
      add_column :events, name, :text unless column_exists?(:events, name)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Keep imported event metadata when rolling back application code."
  end
end
