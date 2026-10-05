module Api
  module Staff
    # Bearer-only API: no web cookie authentication or ambient browser session.
    class BaseController < ActionController::API
      before_action :require_enabled_api
      around_action :with_staff_session
      rescue_from ActionController::ParameterMissing, ArgumentError, with: :invalid_request

      private
        def require_enabled_api
          response.headers["Cache-Control"] = "no-store"
          return head :not_found unless NativeStaffSession.enabled?
          return head :service_unavailable if NativeStaffSession.configured_dates.empty?
          head :forbidden if Rails.env.production? && !request.ssl?
        end

        def with_staff_session
          token = request.authorization.to_s[/\ABearer ([A-Za-z0-9_-]{43})\z/, 1]
          @staff_session = NativeStaffSession.find_by(token_digest: Digest::SHA256.hexdigest(token)) if token
          return unauthorized unless @staff_session

          @operator = @staff_session.admin_user
          @operator.with_lock do
            @staff_session.with_lock do
              return unauthorized unless @staff_session.valid_for_operator?
              yield
            end
          end
        rescue ActiveRecord::RecordNotFound
          unauthorized
        end

        def require_capability(capability)
          @date = Date.iso8601(params.expect(:date)).iso8601
          return true if @staff_session.allows?(capability, @date)

          render json: { state: "error", message: "Event day or capability not permitted" }, status: :forbidden
          false
        end

        def unauthorized
          render json: { state: "error", message: "Staff session expired or revoked. Sign in again." }, status: :unauthorized
        end

        def invalid_request
          render json: { state: "error", message: "Invalid request" }, status: :unprocessable_content
        end
    end
  end
end
