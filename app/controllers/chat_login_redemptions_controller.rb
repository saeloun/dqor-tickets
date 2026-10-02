class ChatLoginRedemptionsController < ActionController::API
  rate_limit to: 120, within: 1.minute
  before_action -> { response.headers["Cache-Control"] = "no-store" }

  def create
    payload = ChatLoginGrant.redeem(code: params[:login_code].to_s, state: params[:state].to_s)
    if payload
      render json: payload
    else
      head :unauthorized
    end
  end
end
