class WidenSessionsForUsers < ActiveRecord::Migration[8.1]
  def up
    change_column_null :sessions, :admin_user_id, true
    add_column :sessions, :user_id, :bigint
    add_index :sessions, :user_id
    add_foreign_key :sessions, :users, validate: false
  end

  def down
    remove_foreign_key :sessions, :users
    remove_index :sessions, :user_id
    remove_column :sessions, :user_id
    change_column_null :sessions, :admin_user_id, false
  end
end
