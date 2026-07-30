class MediaItem < ApplicationRecord
  belongs_to :event
  belongs_to :user, optional: true

  has_one_attached :file

  enum :kind, { image: "image", video: "video" }, validate: true
  enum :source, { upload: "upload", instagram: "instagram", twitter: "twitter", other: "other" }, validate: true
  enum :moderation_state, { pending: "pending", approved: "approved", rejected: "rejected" }, validate: true

  scope :ordered, -> { order(:position, :id) }
end
