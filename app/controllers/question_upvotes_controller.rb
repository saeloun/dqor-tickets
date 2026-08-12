class QuestionUpvotesController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def create
    question = TalkQuestion.find(params[:question_id])
    question.question_upvotes.find_or_create_by!(user: current_user) if current_user.attending?
    respond_with_vote(question)
  rescue ActiveRecord::RecordNotFound
    redirect_to schedule_path, alert: "That question isn’t available."
  end

  def destroy
    question = TalkQuestion.find(params[:question_id])
    question.question_upvotes.where(user: current_user).destroy_all
    respond_with_vote(question)
  rescue ActiveRecord::RecordNotFound
    redirect_to schedule_path, alert: "That question isn’t available."
  end

  private
    def respond_with_vote(question)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(question, :vote),
            partial: "talks/vote", locals: { question: question.reload, current_user: current_user }
          )
        end
        format.html { redirect_to talk_path(question.talk) }
      end
    end
end
