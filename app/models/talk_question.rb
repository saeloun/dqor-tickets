class TalkQuestion < ApplicationRecord
  belongs_to :talk, touch: true
  belongs_to :user

  validates :body, presence: true, length: { maximum: 500 }

  scope :recent, -> { order(created_at: :desc) }

  after_create_commit :broadcast_new_question

  def answered?
    answered_at.present?
  end

  private
    def broadcast_new_question
      broadcast_prepend_to(
        [ talk, :questions ],
        target: "talk-questions",
        partial: "talks/question",
        locals: { question: self }
      )
    end
end
