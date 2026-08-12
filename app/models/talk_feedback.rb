class TalkFeedback < ApplicationRecord
  belongs_to :talk
  belongs_to :user

  validates :rating, inclusion: { in: 1..5 }
  validates :comment, length: { maximum: 1000 }
  validates :user_id, uniqueness: { scope: :talk_id }
end
