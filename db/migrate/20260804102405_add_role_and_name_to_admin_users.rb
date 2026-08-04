class AddRoleAndNameToAdminUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_users, :role, :integer, default: 0, null: false
    add_column :admin_users, :name, :string
  end
end
