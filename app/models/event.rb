class Event < ApplicationRecord
  belongs_to :organizer

  has_one_attached :cover_image

  has_many :tax_profiles, dependent: :restrict_with_exception
  has_many :ticket_types, dependent: :restrict_with_exception
  has_many :coupons, dependent: :restrict_with_exception
  has_many :orders, dependent: :restrict_with_exception
  has_many :tickets, dependent: :restrict_with_exception
  has_many :invoices, dependent: :restrict_with_exception
  has_many :refunds, dependent: :restrict_with_exception
  has_many :payment_events, dependent: :restrict_with_exception
  has_many :registrations, dependent: :restrict_with_exception
  has_many :tracks, dependent: :destroy
  has_many :rooms, dependent: :destroy
  has_many :speakers, dependent: :destroy
  has_many :program_sessions, dependent: :destroy
  has_many :sponsorship_tiers, dependent: :destroy
  has_many :sponsors, dependent: :destroy
  has_many :questions, dependent: :destroy
  has_many :checkin_records, dependent: :destroy
  has_many :waitlist_entries, dependent: :destroy

  enum :status, { draft: "draft", published: "published", archived: "archived", cancelled: "cancelled" }, validate: true
  enum :format, { in_person: "in_person", online: "online", hybrid: "hybrid" }, validate: true

  normalizes :slug, with: ->(slug) { slug.strip.downcase }

  validates :title, :slug, :timezone, :currency, presence: true
  validates :slug, uniqueness: { scope: :organizer_id }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :visibility, inclusion: { in: %w[public unlisted private] }
  validates :venue_state_code, format: { with: /\A\d{2}\z/ }, allow_blank: true
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :capacity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true
  validate :dates_are_ordered

  def conference_module?
    !!settings&.dig("conference_module")
  end

  private
    def dates_are_ordered
      errors.add(:ends_at, "must be after start") if starts_at && ends_at && ends_at < starts_at
    end
end
