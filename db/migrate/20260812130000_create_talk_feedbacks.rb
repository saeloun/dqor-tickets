class CreateTalkFeedbacks < ActiveRecord::Migration[8.1]
  def change
    execute "SET LOCAL lock_timeout = '8s'"

    create_table :talk_feedbacks do |t|
      t.references :talk, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :rating, null: false
      t.text :comment
      t.timestamps
    end

    add_index :talk_feedbacks, [ :talk_id, :user_id ], unique: true
  end
end
