class ConciergeController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 15, within: 5.minutes, only: :create, with: -> { redirect_to concierge_path, alert: "That’s a lot of questions — give it a minute and try again." }

  def show
  end

  def create
    @question = params[:question].to_s.strip
    @answer = Ai::Concierge.answer(@question) if @question.present?
    render :show
  end
end
