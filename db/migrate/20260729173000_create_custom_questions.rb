class CreateCustomQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :questions do |t|
      t.references :event, null: false, foreign_key: true
      t.string :label, null: false
      t.string :help_text
      t.string :kind, null: false, default: "short_text"
      t.boolean :required, null: false, default: false
      t.jsonb :options, null: false, default: []
      t.string :answer_scope, null: false, default: "attendee"
      t.string :ask_at, null: false, default: "checkout"
      t.integer :applies_to_ticket_type_ids, array: true, null: false, default: []
      t.references :dependency_question, foreign_key: { to_table: :questions }
      t.jsonb :dependency_values, null: false, default: []
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :answers do |t|
      t.references :question, null: false, foreign_key: true
      t.references :order, foreign_key: true
      t.references :ticket, foreign_key: true
      t.text :value
      t.jsonb :value_json
      t.timestamps
      t.index [ :question_id, :order_id ], unique: true, where: "order_id IS NOT NULL", name: "index_answers_on_question_and_order"
      t.index [ :question_id, :ticket_id ], unique: true, where: "ticket_id IS NOT NULL", name: "index_answers_on_question_and_ticket"
    end
  end
end
