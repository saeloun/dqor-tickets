class CreateChatLoginGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_login_grants do |t|
      t.string :code_digest, null: false
      t.string :state, null: false
      t.string :email, null: false
      t.string :name
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :chat_login_grants, :code_digest, unique: true
  end
end
