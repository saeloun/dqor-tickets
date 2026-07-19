class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_admin_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }

  def new
  end

  def create
    if admin_user = AdminUser.find_by(email: params[:email])
      PasswordsMailer.reset(admin_user).deliver_later
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if an admin user with that email exists)."
  end

  def edit
  end

  def update
    if @admin_user.update(params.permit(:password, :password_confirmation))
      @admin_user.sessions.destroy_all
      redirect_to new_session_path, notice: "Password has been reset."
    else
      redirect_to edit_password_path(params[:token]), alert: "Passwords did not match."
    end
  end

  private
    def set_admin_user_by_token
      @admin_user = AdminUser.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
