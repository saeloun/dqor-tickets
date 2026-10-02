class ChatLoginsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 30, within: 1.minute, only: :show
  before_action -> { response.headers["Cache-Control"] = "no-store" }

  def show
    session.delete(:chat_login_state)
    return head :bad_request unless ChatLoginGrant::STATE_FORMAT.match?(params[:state].to_s)

    session[:chat_login_state] = params[:state]
  end
end
