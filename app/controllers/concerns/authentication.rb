module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :resume_session
    before_action :require_authentication
    helper_method :authenticated?, :current_user, :current_admin_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def current_user
      Current.session&.user
    end

    def current_admin_user
      Current.session&.admin_user
    end

    def require_authentication
      resume_session || request_authentication
    end

    def require_user_authentication
      resume_session || redirect_to(login_path(return_to: request.url))
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || rails_health_check_url
    end

    def start_new_session_for(account)
      return_to = session.delete(:return_to_after_authenticating)
      request.reset_session
      session_record = account.sessions.create!(
        user_agent: request.user_agent,
        ip_address: request.remote_ip
      )
      Current.session = session_record
      cookies.signed.permanent[:session_id] = { value: session_record.id, httponly: true, same_site: :lax }
      session[:return_to_after_authenticating] = return_to if return_to.present?
      session_record
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
