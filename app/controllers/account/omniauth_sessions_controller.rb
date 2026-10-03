class Account::OmniauthSessionsController < ApplicationController
  allow_unauthenticated_access

  def create
    auth = request.env["omniauth.auth"]
    info = auth&.info
    email = info&.email.to_s.strip.downcase
    chat_state = session.delete(:chat_login_state)

    # Pilot registration requires our email-link verification. Keep the origin
    # context intact through cancellation/retries; never create a public user.
    if session[:free_pilot_sign_in]
      redirect_to account_sign_in_path, alert: "Use the email sign-in link to continue to free events."
      return
    end

    if chat_state
      response.headers["Cache-Control"] = "no-store"
      if ChatLoginGrant::STATE_FORMAT.match?(chat_state) && email.match?(URI::MailTo::EMAIL_REGEXP) &&
          auth&.dig("extra", "raw_info", "email_verified") == true && ChatLoginGrant.allowed_identity?(email)
        code = ChatLoginGrant.issue!(email: email, name: info.name, state: chat_state)
        redirect_to "https://chat.deccanqueenonrails.com/session/google/callback?#{ { login_code: code, state: chat_state }.to_query }", allow_other_host: true
      else
        redirect_to account_sign_in_path, alert: "Google must verify your email before you can join conference chat."
      end
      return
    end

    if email.match?(URI::MailTo::EMAIL_REGEXP)
      user = User.find_or_create_by!(email: email)
      user.update(name: info.name) if user.name.blank? && info.name.present?
      sign_in(user)
      redirect_to account_root_path, notice: "You’re signed in."
    else
      redirect_to account_sign_in_path, alert: "We couldn’t read your Google account. Try the email link instead."
    end
  end

  def failure
    session.delete(:chat_login_state)
    redirect_to account_sign_in_path, alert: "Google sign-in didn’t complete. Try again or use the email link."
  end
end
