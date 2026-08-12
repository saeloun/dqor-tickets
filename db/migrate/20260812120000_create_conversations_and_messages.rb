class CreateConversationsAndMessages < ActiveRecord::Migration[8.1]
  def change
    execute "SET LOCAL lock_timeout = '8s'"

    create_table :conversations do |t|
      t.references :participant_one, null: false, foreign_key: { to_table: :users }
      t.references :participant_two, null: false, foreign_key: { to_table: :users }
      t.datetime :one_last_read_at
      t.datetime :two_last_read_at
      t.timestamps
    end

    add_index :conversations, [ :participant_one_id, :participant_two_id ], unique: true

    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.timestamps
    end

    add_index :messages, [ :conversation_id, :created_at ]
  end
end
