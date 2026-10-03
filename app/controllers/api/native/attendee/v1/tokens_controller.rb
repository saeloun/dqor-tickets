module Api
  module Native
    module Attendee
      module V1
        class TokensController < ActionController::API
          include NativeAttendeePrivateResponse
          wrap_parameters false

          def create
            NativeAttendee::RateLimit.check!("exchange-ip", request.remote_ip, maximum: 20, within: 3.minutes)
            return native_error("invalid_request", :bad_request) unless request.media_type == "application/json" && request.query_string.empty? && !request.has_header?("HTTP_AUTHORIZATION")

            inputs = request.request_parameters
            return native_error("invalid_request", :bad_request) unless inputs.keys.sort == %w[client_id code code_verifier redirect_uri]

            code = inputs["code"]
            return invalid_grant unless code.is_a?(String) && NativeAttendeeAuthorization::CODE_FORMAT.match?(code)

            attempt = NativeAttendeeAuthorization.find_by(code_digest: NativeAttendeeAuthorization.digest(code))
            NativeAttendee::RateLimit.check!("exchange-attempt", attempt&.id || code, maximum: 5, within: 3.minutes)
            result = NativeAttendeeAuthorization.exchange(code: code, code_verifier: request.request_parameters["code_verifier"],
              client_id: request.request_parameters["client_id"], callback_uri: request.request_parameters["redirect_uri"])
            return invalid_grant unless result

            record, token = result
            native_json({ access_token: token, token_type: "Bearer", expires_at: record.expires_at.iso8601,
              event: NativeAttendeeSession::EVENT, capabilities: NativeAttendeeSession::CAPABILITIES })
          rescue ActionDispatch::Http::Parameters::ParseError
            native_error("invalid_request", :bad_request)
          end

          private
            def invalid_grant
              native_error("invalid_grant", :unauthorized)
            end
        end
      end
    end
  end
end
