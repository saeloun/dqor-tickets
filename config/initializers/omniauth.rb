# Google sign-in is dormant until GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET are set.
# In test we load the middleware with dummy credentials so request specs can
# exercise the callback via OmniAuth.config.test_mode.
google_client_id = ENV["GOOGLE_CLIENT_ID"].presence || (Rails.env.test? ? "test-client-id" : nil)
google_client_secret = ENV["GOOGLE_CLIENT_SECRET"].presence || (Rails.env.test? ? "test-client-secret" : nil)

if google_client_id && google_client_secret
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :google_oauth2, google_client_id, google_client_secret,
      scope: "email,profile",
      prompt: "select_account"
  end

  OmniAuth.config.allowed_request_methods = [ :post ]
  OmniAuth.config.silence_get_warning = true
  OmniAuth.config.on_failure = proc do |env|
    Account::OmniauthSessionsController.action(:failure).call(env)
  end
end
