module Api
  module Native
    module Attendee
      module V1
        class BaseController < ActionController::API
          include NativeAttendeePrivateResponse
          around_action :with_native_session

          private
            def with_native_session
              token = request.authorization.to_s[/\ABearer (na1_[A-Za-z0-9_-]{43})\z/, 1]
              record = NativeAttendeeSession.find_by(token_digest: NativeAttendeeAuthorization.digest(token)) if token
              return native_error("unauthenticated", :unauthorized) unless record

              User.transaction do
                @attendee = User.lock.find_by(id: record.user_id)
                record.with_lock do
                  unless record.valid_identity?(@attendee)
                    record.revoke!
                    return native_error("unauthenticated", :unauthorized)
                  end
                  @native_session = record
                  @checked_at = Time.current
                  yield
                end
              end
            rescue ActiveRecord::RecordNotFound
              native_error("unauthenticated", :unauthorized)
            end
        end
      end
    end
  end
end
