class CreateTalks < ActiveRecord::Migration[8.1]
  def change
    create_table :talks do |t|
      t.string :title, null: false
      t.text :abstract
      t.string :speaker_name
      t.text :speaker_bio
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :room
      t.string :track
      t.boolean :published, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :talks, [ :published, :starts_at ]
  end
end
