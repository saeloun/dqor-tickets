class CreateTalkBookmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :talk_bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :talk, null: false, foreign_key: true
      t.timestamps
    end

    add_index :talk_bookmarks, [ :user_id, :talk_id ], unique: true
  end
end
