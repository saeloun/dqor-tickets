class Faq < ApplicationRecord
  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position, :id) }

  validates :question, presence: true
end
