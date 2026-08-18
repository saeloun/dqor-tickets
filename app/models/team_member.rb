class TeamMember < ApplicationRecord
  scope :publicly_listed, -> { where(publicly_listed: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }

  validates :name, presence: true
end
