Avo.configure do |config|
  config.root_path = "/avo"
  config.home_path = "/avo/dashboard"
  config.authorization_client = nil
  config.sign_out_path_name = :session_path
  config.current_user_method do
    Current.admin_user
  end
  config.authenticate_with do
    Current.session ||= Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    unless Current.session
      session[:return_to_after_authenticating] = request.url
      redirect_to main_app.new_session_path
    end
  end
end
