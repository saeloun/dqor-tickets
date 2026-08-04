class Speaker < ApplicationRecord
  has_one_attached :photo
  has_many :talks, dependent: :nullify

  # Private pipeline status. Only `announced` speakers may appear publicly.
  enum :status, { pending: 0, announced: 1, yet_to_announce: 2, on_hold: 3 }, validate: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position, :name) }
  # Public listing must be BOTH explicitly published AND announced — fail-closed.
  scope :publicly_listed, -> { published.announced }

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
