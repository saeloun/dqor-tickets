class VideoAsset < ApplicationRecord
  belongs_to :program_session

  enum :status, {
    pending: "pending",
    uploading: "uploading",
    uploaded: "uploaded",
    published: "published",
    failed: "failed"
  }, validate: true
end
