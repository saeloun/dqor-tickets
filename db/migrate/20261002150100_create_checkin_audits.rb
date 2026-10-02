class CreateCheckinAudits < ActiveRecord::Migration[8.1]
  def change
    create_table :checkin_audits do |t|
      t.references :ticket, foreign_key: { on_delete: :nullify }
      t.references :admin_user, foreign_key: { on_delete: :nullify }
      t.date :event_date, null: false
      t.string :source, null: false
      t.string :outcome, null: false
      t.datetime :created_at, null: false
    end
    add_index :checkin_audits, [ :event_date, :outcome ]
  end
end
