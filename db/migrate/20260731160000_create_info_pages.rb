class CreateInfoPages < ActiveRecord::Migration[8.1]
  def change
    create_table :info_pages do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.text :body
      t.boolean :published, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :info_pages, :slug, unique: true
  end
end
