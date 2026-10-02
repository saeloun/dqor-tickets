class ChatLoginsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :verify_authenticity_token, only: :redeem
  rate_limit to: 30, within: 1.minute, only: :show
  rate_limit to: 120, within: 1.minute, only: :redeem
  before_action -> { response.headers["Cache-Control"] = "no-store" }

  def show
    session.delete(:chat_login_state)
    return head :bad_request unless ChatLoginGrant::STATE_FORMAT.match?(params[:state].to_s)

    session[:chat_login_state] = params[:state]
  end

  def redeem
    payload = ChatLoginGrant.redeem(code: params[:login_code].to_s, state: params[:state].to_s)
    if payload
      render json: payload
    else
      head :unauthorized
    end
  end
end
