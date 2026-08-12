class DropQuestionUpvotes < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '8s'"
    drop_table :question_upvotes, if_exists: true
  end

  def down
    execute "SET LOCAL lock_timeout = '8s'"
    create_table :question_upvotes do |t|
      t.references :talk_question, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :question_upvotes, [ :talk_question_id, :user_id ], unique: true
  end
end
