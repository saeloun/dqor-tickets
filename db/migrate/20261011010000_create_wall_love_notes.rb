class CreateWallLoveNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :wall_love_notes do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :public_name, null: false, limit: 80
      t.text :note, null: false
      t.string :source_url, limit: 500
      t.boolean :publication_consent, null: false, default: false
      t.string :status, null: false, default: "pending"
      t.integer :lock_version, null: false, default: 0
      t.references :reviewed_by, foreign_key: { to_table: :admin_users }
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :wall_love_notes, [ :status, :id ]
    add_check_constraint :wall_love_notes, "status IN ('pending', 'approved', 'rejected', 'unpublished', 'withdrawn')", name: "wall_love_notes_status"
    add_check_constraint :wall_love_notes, "status <> 'approved' OR publication_consent", name: "wall_love_notes_publication_consent"
    add_check_constraint :wall_love_notes, "char_length(note) BETWEEN 1 AND 2000", name: "wall_love_notes_note_length"
  end
end
