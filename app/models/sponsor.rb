class Sponsor < ApplicationRecord
  belongs_to :event
  belongs_to :sponsorship_tier, optional: true
  has_many :sponsor_orders, dependent: :restrict_with_exception

  has_one_attached :logo

  enum :entity_type, { body_corporate: "body_corporate", other: "other" }, validate: true

  normalizes :slug, with: ->(slug) { slug.to_s.strip.downcase }

  before_validation :set_slug, on: :create

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :event_id },
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  scope :ordered, -> { order(:position, :id) }

  private
    def set_slug
      self.slug = name.to_s.parameterize if slug.blank?
    end
end
