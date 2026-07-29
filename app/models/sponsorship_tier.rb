class SponsorshipTier < ApplicationRecord
  belongs_to :event
  has_many :sponsors, dependent: :nullify
  has_many :sponsor_orders, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :level, numericality: { only_integer: true }
  validates :price_minor, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :ordered, -> { order(:level, :position, :id) }
end
