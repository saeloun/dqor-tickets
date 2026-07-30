class AddSpeakerToTalks < ActiveRecord::Migration[8.1]
  def change
    add_reference :talks, :speaker, null: true, foreign_key: true
  end
end
