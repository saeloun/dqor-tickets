class CreateTalkQuestions < ActiveRecord::Migration[8.1]
  def change
    execute "SET LOCAL lock_timeout = '8s'"

    create_table :talk_questions do |t|
      t.references :talk, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.datetime :answered_at
      t.timestamps
    end

    create_table :question_upvotes do |t|
      t.references :talk_question, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :question_upvotes, [ :talk_question_id, :user_id ], unique: true
    add_index :talk_questions, [ :talk_id, :created_at ]
  end
end
