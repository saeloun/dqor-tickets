class CreateNativeAttendeeAuthorizations < ActiveRecord::Migration[8.1]
  def change
    create_table :native_attendee_authorizations do |t|
      t.string :client_id, null: false
      t.string :callback_uri, null: false
      t.string :code_challenge, null: false
      t.string :state, null: false
      t.string :creation_digest, null: false
      t.integer :status, null: false, default: 0
      t.datetime :expires_at, null: false
      t.references :user, foreign_key: { on_delete: :cascade }
      t.string :email_request_digest
      t.string :email_snapshot
      t.string :verification_nonce_digest
      t.string :password_fingerprint
      t.string :consent_digest
      t.datetime :verified_at
      t.string :code_digest
      t.datetime :code_expires_at
      t.datetime :consumed_at
      t.datetime :canceled_at
      t.timestamps
    end
    add_index :native_attendee_authorizations, :code_digest, unique: true, where: "code_digest IS NOT NULL"
    add_check_constraint :native_attendee_authorizations, "status IN (0, 1, 2, 3, 4, 5)", name: "native_attendee_authorization_status"
    add_check_constraint :native_attendee_authorizations, "status NOT IN (1, 2, 3) OR (user_id IS NOT NULL AND email_snapshot IS NOT NULL AND password_fingerprint IS NOT NULL AND verified_at IS NOT NULL AND consent_digest IS NOT NULL)", name: "native_attendee_verified_binding"
    add_check_constraint :native_attendee_authorizations, "status NOT IN (2, 3) OR (code_digest IS NOT NULL AND code_expires_at IS NOT NULL)", name: "native_attendee_code_binding"
  end
end
