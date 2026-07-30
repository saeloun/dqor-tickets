class Speaker < ApplicationRecord
  has_one_attached :photo
  has_many :talks, dependent: :nullify

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position, :name) }

  validates :name, presence: true

  def twitter_url
    "https://twitter.com/#{twitter.delete_prefix("@")}" if twitter.present?
  end

  def github_url
    "https://github.com/#{github.delete_prefix("@")}" if github.present?
  end

  def published_talks
    talks.select(&:published?)
  end
end
