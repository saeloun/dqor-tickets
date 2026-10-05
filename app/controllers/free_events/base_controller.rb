class FreeEvents::BaseController < ApplicationController
  layout "organizer_platform"
  allow_unauthenticated_access
  prepend_before_action :require_free_pilot
  before_action :require_verified_user
  before_action -> { FreeEvents::Privacy.enroll!(current_user) }
  before_action :private_response

  private
    def require_free_pilot
      head :not_found unless FreeEvents::Access.enabled?
    end

    def require_verified_user
      return if current_user && session[:verified_attendee_email] == current_user.email
      session[:free_pilot_sign_in] = true
      session[:free_pilot_return_to] = if is_a?(FreeEvents::RegistrationsController) && action_name == "create"
        published_event_path(params[:organization_slug], params[:event_slug])
      elsif request.get?
        request.path
      else
        free_organizations_path
      end
      redirect_to account_sign_in_path, alert: "Verify your email using a sign-in link to use free events."
    end

    def private_response
      response.headers["Cache-Control"] = "no-store"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end
end
