class TalksController < ApplicationController
  allow_unauthenticated_access

  def show
    @talk = Talk.published.find(params[:id])
    @questions = @talk.talk_questions.recent.includes(:user)
    @question = TalkQuestion.new
  rescue ActiveRecord::RecordNotFound
    redirect_to schedule_path, alert: "That talk isn’t available."
  end
end
