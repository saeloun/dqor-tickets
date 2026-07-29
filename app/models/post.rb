class Post < ApplicationRecord
  belongs_to :event
  belongs_to :user

  has_many :comments, dependent: :destroy
  has_many :reactions, as: :reactable, dependent: :destroy

  validates :body, presence: true

  scope :pinned_first, -> { order(pinned: :desc, created_at: :desc) }
  scope :recent, -> { order(created_at: :desc) }
end
