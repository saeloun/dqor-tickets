class Track < ApplicationRecord
  belongs_to :event
  has_many :program_sessions, dependent: :nullify

  validates :name, presence: true

  scope :ordered, -> { order(:position, :id) }
end
