module Api
  module Attendee
    module V1
      class PassesController < BaseController
        def index
          render_private_json NativeAttendee::ReadSnapshot.new(current_user, checked_at: @checked_at).passes(cursor: params[:cursor], cursor_supplied: params.key?(:cursor))
        rescue NativeAttendee::ReadSnapshot::InvalidCursor
          api_error("invalid_cursor", :unprocessable_content)
        end
      end
    end
  end
end
