class Sponsor < ApplicationRecord
  has_one_attached :logo

  TIERS = %w[platinum gold silver community].freeze

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position, :name) }

  validates :name, presence: true
  validates :tier, inclusion: { in: TIERS }, allow_blank: true

  def tier_label
    tier.presence || "community"
  end
end
