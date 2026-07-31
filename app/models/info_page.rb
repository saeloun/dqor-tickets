class InfoPage < ApplicationRecord
  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position, :title) }

  normalizes :slug, with: ->(value) { value.to_s.strip.downcase }

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  def to_param
    slug
  end
end
