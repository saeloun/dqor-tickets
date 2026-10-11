class CommunityGroup < ApplicationRecord
  belongs_to :organization
  has_many :events, dependent: :restrict_with_exception

  enum :status, { draft: "draft", published: "published" }, validate: true
  normalizes :slug, with: ->(value) { value.to_s.strip.downcase }
  validates :name, :slug, :timezone, presence: true
  validates :name, length: { maximum: 120 }
  validates :slug, length: { maximum: 80 }, uniqueness: { scope: :organization_id }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :tagline, length: { maximum: 160 }
  validates :description, length: { maximum: 2_000 }
  validates :country_code, format: { with: /\A[A-Z]{2}\z/ }, allow_blank: true
  validates :city, length: { maximum: 120 }
  validates :city, :country_code, :description, presence: true, if: :published?
  validate :valid_timezone

  private
    def valid_timezone
      TZInfo::Timezone.get(timezone.to_s)
    rescue TZInfo::InvalidTimezoneIdentifier
      errors.add(:timezone, "must be an IANA timezone, such as Asia/Kolkata")
    end
end
