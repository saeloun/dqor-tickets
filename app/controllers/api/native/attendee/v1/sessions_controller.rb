module Api
  module Native
    module Attendee
      module V1
        class SessionsController < BaseController
          def show
            native_json({ schema_version: 1, event: NativeAttendeeSession::EVENT, client_id: @native_session.client_id,
              capabilities: NativeAttendeeSession::CAPABILITIES, expires_at: @native_session.expires_at.iso8601, checked_at: @checked_at.iso8601 })
          end

          def destroy
            @native_session.revoke!
            head :no_content
          end
        end
      end
    end
  end
end
