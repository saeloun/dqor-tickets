class TeamMember < ApplicationRecord
  scope :publicly_listed, -> { where(publicly_listed: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }
  #has_one_attached :photo

  validates :name, presence: true
end
