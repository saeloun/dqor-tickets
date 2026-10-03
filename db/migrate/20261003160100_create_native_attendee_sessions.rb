class CreateNativeAttendeeSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :native_attendee_sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :native_attendee_authorization, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false
      t.string :email_snapshot, null: false
      t.string :password_fingerprint, null: false
      t.string :client_id, null: false
      t.string :event, null: false, default: "dqor-2026"
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :native_attendee_sessions, :token_digest, unique: true
    add_check_constraint :native_attendee_sessions, "event = 'dqor-2026'", name: "native_attendee_session_event"
  end
end
