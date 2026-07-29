class GallerySource < ApplicationRecord
  belongs_to :event

  enum :provider, { instagram: "instagram", twitter: "twitter", other: "other" }, validate: true

  validates :query, presence: true
end
