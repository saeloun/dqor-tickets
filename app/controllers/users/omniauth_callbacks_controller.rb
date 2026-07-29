class Users::OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access only: %i[github failure]

  def github
    auth = request.env["omniauth.auth"]
    user = UserFromOmniauth.find_or_create!(auth)

    if user.persisted?
      start_new_session_for(user)
      redirect_to after_authentication_url
    else
      redirect_to login_path, alert: "Could not sign in with GitHub."
    end
  rescue UserFromOmniauth::UnverifiedEmail
    redirect_to login_path, alert: "Please verify your GitHub email before signing in."
  end

  def failure
    redirect_to login_path, alert: "GitHub sign in failed. Try a magic link instead."
  end
end
