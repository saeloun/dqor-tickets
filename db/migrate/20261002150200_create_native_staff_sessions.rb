class CreateNativeStaffSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :native_staff_sessions do |t|
      t.references :admin_user, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false
      t.string :password_fingerprint, null: false
      t.string :role, null: false
      t.string :event, null: false
      t.jsonb :event_dates, null: false, default: []
      t.jsonb :capabilities, null: false, default: []
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :native_staff_sessions, :token_digest, unique: true
    add_index :native_staff_sessions, :expires_at
  end
end
