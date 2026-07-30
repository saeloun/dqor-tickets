class Announcement < ApplicationRecord
  scope :published, -> { where(published: true) }
  scope :recent, -> { order(Arel.sql("coalesce(published_at, created_at) DESC")) }

  validates :title, presence: true

  def shown_at
    (published_at || created_at).in_time_zone("Asia/Kolkata")
  end
end
