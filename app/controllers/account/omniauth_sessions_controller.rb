class Account::OmniauthSessionsController < ApplicationController
  allow_unauthenticated_access

  def create
    return create_staff_session if staff_google_sign_in?

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
    original_params = request.env["omniauth.params"] || session.delete("omniauth.params") || {}
    if original_params["login_context"] == "staff"
      session.delete("omniauth.state")
      return reject_staff_google_sign_in
    end

    session.delete(:chat_login_state)
    redirect_to account_sign_in_path, alert: "Google sign-in didn’t complete. Try again or use the email link."
  end

  private
    def staff_google_sign_in?
      request.env.fetch("omniauth.params", {})["login_context"] == "staff"
    end

    def create_staff_session
      auth = request.env["omniauth.auth"]
      email = auth&.info&.email.to_s.strip.downcase
      verified = auth&.provider == "google_oauth2" && auth&.dig("extra", "raw_info", "email_verified") == true
      admin_user = AdminUser.find_by(email:) if verified && email.match?(URI::MailTo::EMAIL_REGEXP)
      return reject_staff_google_sign_in unless admin_user

      admin_user.with_lock do
        return reject_staff_google_sign_in unless admin_user.email == email && (admin_user.admin? || admin_user.desk?)

        return_to = session[:return_to_after_authenticating]
        reset_session
        session[:return_to_after_authenticating] = return_to if return_to.present?
        start_new_session_for(admin_user)
      end
      response.headers["Cache-Control"] = "no-store"
      redirect_to after_authentication_url
    rescue ActiveRecord::RecordNotFound
      reject_staff_google_sign_in
    end

    def reject_staff_google_sign_in
      response.headers["Cache-Control"] = "no-store"
      redirect_to new_session_path, alert: "Google sign-in requires an existing staff account with a verified matching email. Try your staff password or contact an administrator."
    end
end
