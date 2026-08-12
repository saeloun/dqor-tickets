class TalkQuestionsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def create
    talk = Talk.published.find(params[:talk_id])

    unless current_user.attending?
      redirect_to talk_path(talk), alert: "Only attendees with a pass can ask questions."
      return
    end

    @question = talk.talk_questions.build(user: current_user, body: question_params[:body])

    if @question.save
      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html { redirect_to talk_path(talk) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("ask-question",
            partial: "talks/ask", locals: { talk: talk, question: @question }), status: :unprocessable_content
        end
        format.html { redirect_to talk_path(talk), alert: @question.errors.full_messages.to_sentence }
      end
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to schedule_path, alert: "That talk isn’t available."
  end

  private
    def question_params
      params.expect(talk_question: [ :body ])
    end
end
