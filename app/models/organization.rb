class Organization < ApplicationRecord
  has_many :memberships, dependent: :restrict_with_exception
  has_many :events, dependent: :restrict_with_exception

  normalizes :slug, with: ->(value) { value.to_s.strip.downcase }
  validates :name, :slug, presence: true, length: { maximum: 255 }
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
end
