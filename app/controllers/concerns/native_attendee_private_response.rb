module NativeAttendeePrivateResponse
  extend ActiveSupport::Concern

  included do
    prepend_before_action :prepare_native_response
    after_action :protect_native_response
    rescue_from NativeAttendee::RateLimit::Exceeded, with: :native_rate_exceeded
    rescue_from NativeAttendee::RateLimit::Unavailable, with: :native_rate_unavailable
  end

  private
    def prepare_native_response
      protect_native_response
      return native_error("not_found", :not_found) unless NativeAttendee::Clients.enabled?
      return native_error("https_required", :forbidden) if Rails.env.production? && !request.ssl?
      native_error("configuration_unavailable", :service_unavailable) if NativeAttendee::Clients.mapping.empty?
    end

    def protect_native_response
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["Referrer-Policy"] = NativeAttendee::RequestPrivacy.referrer_policy(request.path)
      callback = @authorization&.callback_uri
      callbacks = NativeAttendee::Clients.mapping.value?(callback) ? callback : ""
      response.headers["Content-Security-Policy"] = "default-src 'none'; base-uri 'none'; form-action 'self' #{callbacks}; frame-ancestors 'none'"
      response.headers.delete("ETag")
      response.headers.delete("Last-Modified")
      self.response_body = [ response.body ].each if response_body.present? && response.body.is_a?(String)
    end

    def native_json(payload, status: :ok)
      render json: payload, status: status
      self.response_body = [ response.body ].each
    end

    def native_error(code, status)
      native_json({ schema_version: 1, error: { code: code } }, status: status)
    end

    def native_rate_exceeded
      response.headers["Retry-After"] = "180"
      native_error("rate_limited", :too_many_requests)
    end

    def native_rate_unavailable
      native_error("temporarily_unavailable", :service_unavailable)
    end
end
