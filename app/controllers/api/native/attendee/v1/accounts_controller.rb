module Api
  module Native
    module Attendee
      module V1
        class AccountsController < BaseController
          def show
            native_json NativeAttendee::ReadSnapshot.new(@attendee, checked_at: @checked_at).account
          end
        end
      end
    end
  end
end
