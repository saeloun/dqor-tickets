module Api
  module Attendee
    module V1
      class AccountsController < BaseController
        def show
          render_private_json envelope.merge(account: { id: current_user.id.to_s, name: current_user.name, email: current_user.email })
        end
      end
    end
  end
end
