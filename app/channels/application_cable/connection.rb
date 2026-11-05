module ApplicationCable
  # Only signed-in, active people may open a live connection. Which streams they may listen to is
  # decided by the page: stream names are signed, so a name can't be guessed or edited.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_user
        session = Session.includes(:user).find_by(id: cookies.signed[:session_id])
        self.current_user = session.user if session&.user&.active?
      end
  end
end
