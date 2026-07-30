class ProgramSessionSpeaker < ApplicationRecord
  belongs_to :program_session
  belongs_to :speaker

  enum :role, { speaker: "speaker", co_speaker: "co_speaker", moderator: "moderator" }, validate: true

  validates :speaker_id, uniqueness: { scope: :program_session_id }

  scope :ordered, -> { order(:position, :id) }
end
