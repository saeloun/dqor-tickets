class AddCommunityGroupEventForeignKey < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    execute "SET LOCAL statement_timeout = '20s'"
    add_foreign_key :events, :community_groups, column: [ :community_group_id, :organization_id ], primary_key: [ :id, :organization_id ], name: "events_same_organization_group", validate: false
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Retain tenant enforcement when rolling back application code"
  end
end
