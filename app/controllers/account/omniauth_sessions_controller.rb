class Account::OmniauthSessionsController < ApplicationController
  allow_unauthenticated_access

  def create
    auth = request.env["omniauth.auth"]
    info = auth&.info
    email = info&.email.to_s.strip.downcase

    if email.match?(URI::MailTo::EMAIL_REGEXP)
      user = User.find_or_create_by!(email: email)
      user.update(name: info.name) if user.name.blank? && info.name.present?
      user.update(github: info.nickname) if auth.provider == "github" && user.github.blank? && info.nickname.present?
      sign_in(user)
      redirect_to account_root_path, notice: "You’re signed in."
    else
      redirect_to account_sign_in_path, alert: "We couldn’t read that account’s email. Try the email link instead."
    end
  end

  def failure
    redirect_to account_sign_in_path, alert: "Social sign-in didn’t complete. Try again or use the email link."
  end
end
