class Speaker < ApplicationRecord
  has_one_attached :photo

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position, :name) }

  validates :name, presence: true

  def twitter_url
    "https://twitter.com/#{twitter.delete_prefix("@")}" if twitter.present?
  end

  def github_url
    "https://github.com/#{github.delete_prefix("@")}" if github.present?
  end
end
