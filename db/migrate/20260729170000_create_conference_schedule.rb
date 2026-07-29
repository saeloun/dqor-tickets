class CreateConferenceSchedule < ActiveRecord::Migration[8.1]
  def change
    create_table :tracks do |t|
      t.references :event, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color
      t.string :text_color
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :rooms do |t|
      t.references :event, null: false, foreign_key: true
      t.string :name, null: false
      t.string :floor
      t.integer :capacity
      t.boolean :is_virtual, null: false, default: false
      t.string :stream_url
      t.text :accessibility_notes
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :speakers do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :name, null: false
      t.text :bio
      t.string :company
      t.string :title
      t.string :pronouns
      t.string :github
      t.string :twitter
      t.string :mastodon
      t.string :bluesky
      t.string :linkedin
      t.string :speakerdeck
      t.string :website
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :program_sessions do |t|
      t.references :event, null: false, foreign_key: true
      t.references :track, foreign_key: true
      t.references :room, foreign_key: true
      t.string :title, null: false
      t.text :abstract
      t.text :description
      t.string :kind, null: false, default: "talk"
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :language
      t.string :level
      t.string :state, null: false, default: "confirmed"
      t.string :slides_url
      t.string :video_url
      t.string :video_provider
      t.integer :max_attendees
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :program_session_speakers do |t|
      t.references :program_session, null: false, foreign_key: true
      t.references :speaker, null: false, foreign_key: true
      t.string :role, null: false, default: "speaker"
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [ :program_session_id, :speaker_id ], unique: true, name: "index_pss_on_session_and_speaker"
    end
  end
end
