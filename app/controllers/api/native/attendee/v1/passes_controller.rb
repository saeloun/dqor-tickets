module Api
  module Native
    module Attendee
      module V1
        class PassesController < BaseController
          def index
            native_json NativeAttendee::ReadSnapshot.new(@attendee, checked_at: @checked_at).passes(cursor: params[:cursor], cursor_supplied: params.key?(:cursor))
          rescue NativeAttendee::ReadSnapshot::InvalidCursor
            native_error("invalid_cursor", :unprocessable_content)
          end
        end
      end
    end
  end
end
