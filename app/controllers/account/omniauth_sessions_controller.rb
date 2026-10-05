class Account::OmniauthSessionsController < ApplicationController
  allow_unauthenticated_access

  def create
    auth = request.env["omniauth.auth"]
    info = auth&.info
    email = info&.email.to_s.strip.downcase
    chat_state = session.delete(:chat_login_state)
    verified_email = auth&.dig("extra", "raw_info", "email_verified") == true

    # Pilot registration requires our email-link verification. Keep the origin
    # context intact through cancellation/retries; never create a public user.
    if session[:free_pilot_sign_in]
      redirect_to account_sign_in_path, alert: "Use the email sign-in link to continue to free events."
      return
    end

    if chat_state
      response.headers["Cache-Control"] = "no-store"
      unless ChatLoginGrant::STATE_FORMAT.match?(chat_state) && email.match?(URI::MailTo::EMAIL_REGEXP) &&
          verified_email && ChatLoginGrant.allowed_identity?(email)
        redirect_to account_sign_in_path, alert: "Google must verify your email before you can join conference chat."
        return
      end
    end

    if email.match?(URI::MailTo::EMAIL_REGEXP)
      user = User.find_or_create_by!(email: email)
      user.update(name: info.name) if user.name.blank? && info.name.present?
      sign_in(user)
      session[:verified_chat_email] = email if verified_email
      redirect_to(chat_state ? chat_login_path(state: chat_state) : account_root_path, notice: "You’re signed in.")
    else
      redirect_to account_sign_in_path, alert: "We couldn’t read your Google account. Try the email link instead."
    end
  end

  def failure
    session.delete(:chat_login_state)
    redirect_to account_sign_in_path, alert: "Google sign-in didn’t complete. Try again or use the email link."
  end
end
