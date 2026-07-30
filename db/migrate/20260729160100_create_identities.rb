class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      t.bigint :user_id, null: false
      t.string :provider, null: false
      t.string :uid, null: false
      t.jsonb :auth, null: false, default: {}
      t.timestamps
    end
    add_index :identities, [ :provider, :uid ], unique: true
    add_index :identities, :user_id
    add_foreign_key :identities, :users, validate: false
  end
end
