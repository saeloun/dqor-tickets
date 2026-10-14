class Discovery::Source < ApplicationRecord
  self.table_name = "discovery_sources"
  has_many :references, class_name: "Discovery::Reference", dependent: :restrict_with_exception
  validates :key, :name, :url, :revision, :fetched_at, :imported_at, :last_attempt_at, presence: true
  validates :key, uniqueness: true, format: { with: /\A[a-z0-9][a-z0-9_-]{0,59}\z/ }
  validates :name, length: { maximum: 120 }
  validates :revision, length: { maximum: 200 }

  def stale?
    last_error_code.present? || fetched_at < 14.days.ago
  end
end
