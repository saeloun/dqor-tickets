class TalkFeedbacksController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def create
    talk = Talk.published.find(params[:talk_id])

    unless current_user.attending? && talk.over?
      redirect_to schedule_path, alert: "You can rate a talk once you have a pass and the talk has finished."
      return
    end

    feedback = talk.talk_feedbacks.find_or_initialize_by(user: current_user)
    feedback.assign_attributes(feedback_params)

    if feedback.save
      redirect_to schedule_path, notice: "Thanks for rating #{talk.title}."
    else
      redirect_to schedule_path, alert: feedback.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to schedule_path, alert: "Talk not found."
  end

  private
    def feedback_params
      params.expect(talk_feedback: [ :rating, :comment ])
    end
end
