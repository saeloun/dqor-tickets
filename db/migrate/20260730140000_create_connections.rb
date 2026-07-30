class CreateConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :connections do |t|
      t.references :user, null: false, foreign_key: true
      t.references :connected_user, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :connections, [ :user_id, :connected_user_id ], unique: true
  end
end
