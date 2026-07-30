class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :user_signed_in?

  private
    def current_user
      @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
    end

    def user_signed_in?
      current_user.present?
    end

    def sign_in(user)
      reset_session
      session[:user_id] = user.id
      @current_user = user
    end

    def sign_out_user
      reset_session
      @current_user = nil
    end

    def require_user
      current_user || redirect_to(account_sign_in_path, alert: "Please sign in to continue.")
    end
end
