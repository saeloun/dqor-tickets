class Speaker < ApplicationRecord
  belongs_to :event
  belongs_to :user, optional: true

  has_many :program_session_speakers, dependent: :destroy
  has_many :program_sessions, through: :program_session_speakers

  has_one_attached :photo

  normalizes :github, with: ->(value) { value.to_s.strip.delete_prefix("@").presence }

  validates :name, presence: true

  scope :ordered, -> { order(:position, :id) }
end
