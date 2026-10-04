class ChatLoginsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 30, within: 1.minute, only: :show
  before_action -> { response.headers["Cache-Control"] = "no-store" }

  def show
    session.delete(:chat_login_state)
    return head :bad_request unless ChatLoginGrant::STATE_FORMAT.match?(params[:state].to_s)

    if current_user && [ session[:verified_attendee_email], session[:verified_chat_email] ].include?(current_user.email)
      unless ChatLoginGrant.allowed_identity?(current_user.email)
        return redirect_to account_root_path, alert: "Your DQOR account does not have conference chat access."
      end

      code = ChatLoginGrant.issue!(email: current_user.email, name: current_user.name.to_s, state: params[:state])
      redirect_to "https://chat.deccanqueenonrails.com/session/google/callback?#{ { login_code: code, state: params[:state] }.to_query }", allow_other_host: true
    else
      session[:chat_login_state] = params[:state]
      redirect_to account_sign_in_path
    end
  end
end
