class CreateAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :announcements do |t|
      t.string :title, null: false
      t.text :body
      t.boolean :published, null: false, default: false
      t.datetime :published_at
      t.timestamps
    end

    add_index :announcements, [ :published, :published_at ]
  end
end
