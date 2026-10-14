class Discovery::Reference < ApplicationRecord
  self.table_name = "discovery_references"
  belongs_to :source, class_name: "Discovery::Source"
  belongs_to :listing, class_name: "Discovery::Listing"
  validates :external_id, :source_url, :revision, :last_seen_at, presence: true
  validates :external_id, uniqueness: { scope: :source_id }, length: { maximum: 255 }

  def stale?
    source.stale? || last_seen_at < source.fetched_at
  end
end
