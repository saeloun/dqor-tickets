module Api
  module Attendee
    module V1
      class BaseController < ApplicationController
        allow_unauthenticated_access
        skip_before_action :capture_referral
        prepend_before_action :require_attendee_session
        after_action :protect_private_response

        private
          def require_attendee_session
            protect_private_response
            request.format = :json
            return api_error("not_found", :not_found) unless ENV["NATIVE_ATTENDEE_READ_API_ENABLED"] == "true"
            return api_error("https_required", :forbidden) if Rails.env.production? && !request.ssl?
            return api_error("authorization_not_supported", :forbidden) if request.has_header?("HTTP_AUTHORIZATION")
            return api_error("unauthenticated", :unauthorized) unless current_user
            return api_error("email_verification_required", :forbidden) unless session[:verified_attendee_email] == current_user.email

            @checked_at = Time.current
          end

          def protect_private_response
            response.headers["Cache-Control"] = "private, no-store"
            response.headers["Referrer-Policy"] = "no-referrer"
            response.headers.delete("ETag")
            response.headers.delete("Last-Modified")
          end

          def envelope
            { schema_version: 1, event: "dqor-2026", checked_at: @checked_at&.iso8601 }
          end

          def api_error(code, status)
            render_private_json({ schema_version: 1, error: { code: code } }, status: status)
          end

          def render_private_json(payload, status: :ok)
            render json: payload, status: status
            self.response_body = [ response.body ].each
          end

          def allow_browser(versions:, block:)
          end
      end
    end
  end
end
