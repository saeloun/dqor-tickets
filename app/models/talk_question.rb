class TalkQuestion < ApplicationRecord
  belongs_to :talk, touch: true
  belongs_to :user
  has_many :question_upvotes, dependent: :destroy

  validates :body, presence: true, length: { maximum: 500 }

  scope :ranked, -> {
    left_joins(:question_upvotes)
      .group(:id)
      .order(Arel.sql("COUNT(question_upvotes.id) DESC"), created_at: :asc)
  }

  after_create_commit :broadcast_new_question

  def upvotes_count
    question_upvotes.size
  end

  def upvoted_by?(user)
    return false unless user

    question_upvotes.any? { |vote| vote.user_id == user.id }
  end

  def answered?
    answered_at.present?
  end

  private
    def broadcast_new_question
      broadcast_prepend_to(
        [ talk, :questions ],
        target: "talk-questions",
        partial: "talks/question",
        locals: { question: self, current_user: nil }
      )
    end
end
