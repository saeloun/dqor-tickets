class ValidateCommunityGroupEventForeignKey < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    execute "SET LOCAL statement_timeout = '5min'"
    validate_foreign_key :events, :community_groups, name: "events_same_organization_group"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Retain the validated tenant foreign key when rolling back application code"
  end
end
