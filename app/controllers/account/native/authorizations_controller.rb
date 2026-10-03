module Account
  module Native
    class AuthorizationsController < ApplicationController
      include NativeAttendeePrivateResponse
      allow_unauthenticated_access
      skip_before_action :capture_referral
      layout "native_attendee"
      protect_from_forgery with: :exception
      rescue_from NativeAttendeeAuthorization::Invalid, ActiveRecord::RecordNotFound, with: :invalid_attempt
      rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_consent

      def new
        NativeAttendee::RateLimit.check!("start-ip", request.remote_ip, maximum: 20, within: 3.minutes)
        @authorization, proof = NativeAttendeeAuthorization.start!(client_id: params[:client_id], callback_uri: params[:redirect_uri],
          state: params[:state], code_challenge: params[:code_challenge], method: params[:code_challenge_method])
        session[:native_attendee_context] = { "id" => @authorization.id, "proof" => proof }
      end

      def email
        NativeAttendee::RateLimit.check!("email-ip", request.remote_ip, maximum: 10, within: 3.minutes)
        email = params[:email].is_a?(String) ? params[:email].strip.downcase : ""
        NativeAttendee::RateLimit.check!("email-address", email, maximum: 3, within: 15.minutes)
        authorization, proof = context
        if authorization.request_email!(email, proof: proof)
          NativeAttendeeVerificationJob.perform_later(authorization.id, email)
        end
        render :sent, status: :accepted
      end

      def verify
        payload = params[:token].is_a?(String) && NativeAttendeeAuthorization.verifier.verified(params[:token], purpose: NativeAttendeeAuthorization::PURPOSE)
        raise NativeAttendeeAuthorization::Invalid unless payload.is_a?(Hash)

        authorization = NativeAttendeeAuthorization.find(payload["id"])
        proof = authorization.verify!(payload)
        reset_session
        session[:native_attendee_context] = { "id" => authorization.id, "proof" => proof }
        redirect_to native_attendee_consent_path
      end

      def consent
        @authorization, proof = context
        raise NativeAttendeeAuthorization::Invalid unless @authorization.verified_context?(proof)
      end

      def approve
        @authorization, proof = context
        code = @authorization.issue_code!(proof: proof)
        callback = URI.parse(@authorization.callback_uri)
        callback.query = { code: code, state: @authorization.state }.to_query
        redirect_to callback.to_s, allow_other_host: true, status: :see_other
      end

      def cancel
        authorization, proof = context
        authorization.cancel!(proof: proof)
        session.delete(:native_attendee_context)
        render :canceled
      end

      private
        def context
          context = session[:native_attendee_context]
          raise NativeAttendeeAuthorization::Invalid unless context.is_a?(Hash) && context["id"].is_a?(Integer) && context["proof"].is_a?(String)

          [ NativeAttendeeAuthorization.find(context["id"]), context["proof"] ]
        end

        def invalid_attempt
          native_error("invalid_attempt", :conflict)
        end

        def invalid_consent
          native_error("invalid_consent", :forbidden)
        end

        def allow_browser(versions:, block:)
        end
    end
  end
end
