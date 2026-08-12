class QuestionUpvote < ApplicationRecord
  belongs_to :talk_question, touch: true
  belongs_to :user

  validates :user_id, uniqueness: { scope: :talk_question_id }

  after_create_commit :broadcast_count
  after_destroy_commit :broadcast_count

  private
    def broadcast_count
      talk_question.broadcast_update_to(
        [ talk_question.talk, :questions ],
        target: ActionView::RecordIdentifier.dom_id(talk_question, :count),
        html: talk_question.question_upvotes.count.to_s
      )
    end
end
