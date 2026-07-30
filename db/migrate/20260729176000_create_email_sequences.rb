class CreateEmailSequences < ActiveRecord::Migration[8.1]
  def change
    create_table :email_sequence_steps do |t|
      t.references :event, null: false, foreign_key: true
      t.string :trigger_type, null: false, default: "on_registration"
      t.integer :offset_seconds, null: false, default: 0
      t.string :subject, null: false
      t.text :body, null: false
      t.boolean :enabled, null: false, default: false
      t.jsonb :audience_filter, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :email_sequence_sends do |t|
      t.references :email_sequence_step, null: false, foreign_key: true
      t.references :registration, null: false, foreign_key: true
      t.datetime :sent_at
      t.timestamps
      t.index [ :email_sequence_step_id, :registration_id ], unique: true, name: "index_sequence_sends_on_step_and_registration"
    end
  end
end
