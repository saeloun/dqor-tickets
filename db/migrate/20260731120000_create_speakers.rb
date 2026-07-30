class CreateSpeakers < ActiveRecord::Migration[8.1]
  def change
    create_table :speakers do |t|
      t.string :name, null: false
      t.string :title
      t.text :bio
      t.string :twitter
      t.string :github
      t.boolean :published, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :speakers, [ :published, :position ]
  end
end
