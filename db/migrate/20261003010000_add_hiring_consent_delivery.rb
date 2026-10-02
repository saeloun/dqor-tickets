class AddHiringConsentDelivery < ActiveRecord::Migration[8.1]
  def change
    add_column :hiring_applications, :resume_digest, :string
    add_column :hiring_applications, :scan_digest, :string
    add_column :hiring_applications, :scan_status, :string, null: false, default: "quarantined"
    add_column :hiring_applications, :scanned_at, :datetime
    create_table :hiring_share_requests do |t|
      t.references :job, null: false, foreign_key: { to_table: :hiring_jobs }
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.references :applicant, foreign_key: { to_table: :users }
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consented_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :hiring_share_requests, :token_digest, unique: true
    add_reference :hiring_applications, :share_request, foreign_key: { to_table: :hiring_share_requests }, index: { unique: true }
    create_table :hiring_access_events do |t|
      t.references :application, null: false, foreign_key: { to_table: :hiring_applications }
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.timestamps
    end
  end
end
