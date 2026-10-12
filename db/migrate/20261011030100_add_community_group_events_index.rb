class AddCommunityGroupEventsIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "idx_on_organization_id_community_group_id_starts_at_360868f23d"
  COLUMNS = %w[organization_id community_group_id starts_at].freeze

  def up
    previous_lock_timeout = connection.select_value("SHOW lock_timeout")
    previous_statement_timeout = connection.select_value("SHOW statement_timeout")
    begin
      execute "SET lock_timeout = '5s'"
      execute "SET statement_timeout = '10min'"
      index = connection.indexes(:events).find { |candidate| candidate.name == INDEX_NAME }
      if index
        unless index.columns == COLUMNS && !index.unique && index.using == :btree && index.where.nil? && index.include.blank? && index.orders.empty? && index.opclasses.empty?
          raise "Community event index differs from the expected definition; preserve it and inspect before retry"
        end
        return if index.valid?

        remove_index :events, name: INDEX_NAME, algorithm: :concurrently
      end
      add_index :events, COLUMNS, name: INDEX_NAME, algorithm: :concurrently
    ensure
      execute "SET lock_timeout = #{connection.quote(previous_lock_timeout)}"
      execute "SET statement_timeout = #{connection.quote(previous_statement_timeout)}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Retain the community event index when rolling back application code"
  end
end
