class CreateHiring < ActiveRecord::Migration[8.1]
  def change
    create_table :hiring_companies do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :claimant, null: false, foreign_key: { to_table: :users }
      t.references :reviewer, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :website, null: false
      t.string :status, null: false, default: "pending"
      t.text :evidence, null: false
      t.timestamps
    end
    create_table :hiring_jobs do |t|
      t.references :company, null: false, foreign_key: { to_table: :hiring_companies }
      t.references :event, foreign_key: true
      t.references :recruiter, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :description, null: false
      t.boolean :open, default: true, null: false
      t.timestamps
    end
    create_table :hiring_applications do |t|
      t.references :job, null: false, foreign_key: { to_table: :hiring_jobs }
      t.references :applicant, null: false, foreign_key: { to_table: :users }
      t.jsonb :snapshot, null: false, default: {}
      t.datetime :consented_at, null: false
      t.datetime :withdrawn_at
      t.binary :quarantined_pdf
      t.timestamps
    end
    add_index :hiring_applications, [ :job_id, :applicant_id ], unique: true
    create_table :hiring_affiliations do |t|
      t.references :company, null: false, foreign_key: { to_table: :hiring_companies }
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :hiring_affiliations, [ :company_id, :user_id ], unique: true
  end
end
