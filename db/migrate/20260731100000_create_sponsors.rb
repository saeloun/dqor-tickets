class CreateSponsors < ActiveRecord::Migration[8.1]
  def change
    create_table :sponsors do |t|
      t.string :name, null: false
      t.string :url
      t.string :tier
      t.text :blurb
      t.boolean :published, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :sponsors, [ :published, :position ]
  end
end
