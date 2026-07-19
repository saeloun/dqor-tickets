module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_admin_user

    def connect
      set_current_admin_user || reject_unauthorized_connection
    end

    private
      def set_current_admin_user
        if session = Session.find_by(id: cookies.signed[:session_id])
          self.current_admin_user = session.admin_user
        end
      end
  end
end
