module Api
  module Staff
    class SessionsController < BaseController
      skip_around_action :with_staff_session, only: :create
      rate_limit to: 10, within: 3.minutes, only: :create,
        with: -> { render json: { state: "error", message: "Try again later" }, status: :too_many_requests }

      def create
        operator = AdminUser.authenticate_by(params.permit(:email, :password))
        return unauthorized unless operator && (operator.admin? || operator.desk?)

        operator.with_lock do
          # Authentication and issuance must agree even across a concurrent password reset.
          return unauthorized unless (operator.admin? || operator.desk?) && operator.authenticate(params[:password])
          @staff_session, token = NativeStaffSession.issue!(operator)
          render json: session_payload.merge(access_token: token, token_type: "Bearer"), status: :created
        end
      end

      def show
        render json: session_payload
      end

      def destroy
        @staff_session.destroy!
        head :no_content
      end

      private
        def session_payload
          { event: @staff_session.event, event_dates: @staff_session.event_dates & NativeStaffSession.configured_dates,
            capabilities: @staff_session.capabilities & NativeStaffSession::CAPABILITIES,
            expires_at: @staff_session.expires_at.iso8601, max_batch_size: ::CheckinsController::MAX_BATCH_SIZE }
        end
    end
  end
end
