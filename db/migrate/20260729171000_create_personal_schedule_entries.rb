class CreatePersonalScheduleEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :personal_schedule_entries do |t|
      t.references :registration, null: false, foreign_key: true
      t.references :program_session, null: false, foreign_key: true
      t.timestamps
      t.index [ :registration_id, :program_session_id ], unique: true, name: "index_pse_on_registration_and_session"
    end
  end
end
