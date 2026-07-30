class CreateCheckinRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :checkin_records do |t|
      t.references :event, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true
      t.references :program_session, foreign_key: true
      t.references :operator_user, foreign_key: { to_table: :users }
      t.string :direction, null: false, default: "entry"
      t.boolean :successful, null: false, default: true
      t.string :failure_reason
      t.datetime :scanned_at
      t.datetime :recorded_at
      t.string :device_id
      t.timestamps
      t.index [ :ticket_id, :recorded_at ]
    end
  end
end
