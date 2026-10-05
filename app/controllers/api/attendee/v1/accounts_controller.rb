module Api
  module Attendee
    module V1
      class AccountsController < BaseController
        def show
          render_private_json NativeAttendee::ReadSnapshot.new(current_user, checked_at: @checked_at).account
        end
      end
    end
  end
end
