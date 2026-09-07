class AddConversationFieldsToUsers < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '8s'"
    add_column :users, :job_title, :string
    add_column :users, :company, :string
    add_column :users, :conversation_starter, :string
  end

  def down
    remove_columns :users, :job_title, :company, :conversation_starter
  end
end
