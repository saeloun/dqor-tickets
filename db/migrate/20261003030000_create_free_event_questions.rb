class CreateFreeEventQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :free_event_forms do |t|
      t.references :event, null: false, foreign_key: true
      t.references :ticket_type, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :draft_questions, null: false, default: []
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :free_event_forms, [ :id, :event_id, :ticket_type_id ], unique: true, name: "free_form_ownership"
    add_foreign_key :free_event_forms, :ticket_types, column: [ :ticket_type_id, :event_id ], primary_key: [ :id, :ownership_key ], name: "free_form_type_ownership"

    create_table :free_event_form_versions do |t|
      t.references :form, null: false, foreign_key: { to_table: :free_event_forms }
      t.bigint :event_id, null: false
      t.bigint :ticket_type_id, null: false
      t.integer :number, null: false
      t.jsonb :questions, null: false, default: []
      t.datetime :created_at, null: false
    end
    add_index :free_event_form_versions, [ :form_id, :number ], unique: true
    add_index :free_event_form_versions, [ :id, :event_id, :ticket_type_id ], unique: true, name: "free_form_version_ownership"
    add_foreign_key :free_event_form_versions, :free_event_forms, column: [ :form_id, :event_id, :ticket_type_id ], primary_key: [ :id, :event_id, :ticket_type_id ], name: "free_version_form_ownership"

    create_table :free_event_responses do |t|
      t.references :ticket, null: false, foreign_key: true, index: { unique: true }
      t.references :form_version, null: false, foreign_key: { to_table: :free_event_form_versions }
      t.bigint :event_id, null: false
      t.bigint :ticket_type_id, null: false
      t.jsonb :answers, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :tickets, [ :id, :ownership_key, :ticket_type_id ], unique: true, name: "free_response_ticket_ownership_key"
    add_foreign_key :free_event_responses, :tickets, column: [ :ticket_id, :event_id, :ticket_type_id ], primary_key: [ :id, :ownership_key, :ticket_type_id ], name: "free_response_ticket_ownership"
    add_foreign_key :free_event_responses, :free_event_form_versions, column: [ :form_version_id, :event_id, :ticket_type_id ], primary_key: [ :id, :event_id, :ticket_type_id ], name: "free_response_version_ownership"
  end
end
