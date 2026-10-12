class Event < ApplicationRecord
  belongs_to :organization
  belongs_to :community_group, optional: true

  enum :status, { draft: "draft", published: "published" }, validate: true
  normalizes :slug, with: ->(value) { value.to_s.strip.downcase }
  validates :title, :slug, :timezone, presence: true, length: { maximum: 255 }
  validates :slug, uniqueness: { scope: :organization_id }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :starts_at, :ends_at, presence: true, if: :published?
  validate :valid_timezone
  validate :ordered_dates
  validate :group_organization_matches

  private
    def group_organization_matches
      errors.add(:community_group, "must belong to this organization") if community_group && community_group.organization_id != organization_id
    end

    def valid_timezone
      TZInfo::Timezone.get(timezone.to_s)
    rescue TZInfo::InvalidTimezoneIdentifier
      errors.add(:timezone, "must be an IANA timezone, such as Asia/Kolkata")
    end

    def ordered_dates
      errors.add(:ends_at, "must be after start") if starts_at && ends_at && ends_at <= starts_at
    end
end
