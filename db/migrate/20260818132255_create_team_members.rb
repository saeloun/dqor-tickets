class CreateTeamMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :team_members do |t|
      t.string  :name, null: false
      t.string  :role          # e.g. "Organizer", "Volunteer Lead", "Sponsorship"
      t.string  :team          # e.g. "Logistics", "Marketing", "Content"
      t.text    :bio
      t.string  :photo_url
      t.string  :email
      t.string  :twitter_handle
      t.string  :linkedin_url
      t.integer :position, default: 0, null: false   # for manual ordering
      t.boolean :publicly_listed, default: true, null: false

      t.timestamps
    end

    add_index :team_members, :publicly_listed
    add_index :team_members, :position
  end
end
