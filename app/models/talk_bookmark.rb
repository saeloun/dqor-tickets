class TalkBookmark < ApplicationRecord
  belongs_to :user
  belongs_to :talk

  validates :talk_id, uniqueness: { scope: :user_id }
end
