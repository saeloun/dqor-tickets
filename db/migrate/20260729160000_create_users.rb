class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    enable_extension "citext" unless extension_enabled?("citext")

    create_table :users do |t|
      t.citext :email, null: false
      t.string :name, null: false
      t.string :github_login
      t.string :timezone, null: false, default: "Asia/Kolkata"
      t.jsonb :preferences, null: false, default: {}
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
