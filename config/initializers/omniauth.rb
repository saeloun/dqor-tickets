google_client_id = ENV["GOOGLE_CLIENT_ID"].presence || (Rails.env.test? ? "test-client-id" : nil)
google_client_secret = ENV["GOOGLE_CLIENT_SECRET"].presence || (Rails.env.test? ? "test-client-secret" : nil)
github_client_id = ENV["GITHUB_CLIENT_ID"].presence || (Rails.env.test? ? "test-client-id" : nil)
github_client_secret = ENV["GITHUB_CLIENT_SECRET"].presence || (Rails.env.test? ? "test-client-secret" : nil)

if (google_client_id && google_client_secret) || (github_client_id && github_client_secret)
  Rails.application.config.middleware.use OmniAuth::Builder do
    if google_client_id && google_client_secret
      provider :google_oauth2, google_client_id, google_client_secret,
        scope: "email,profile",
        prompt: "select_account"
    end

    provider :github, github_client_id, github_client_secret, scope: "user:email" if github_client_id && github_client_secret
  end

  OmniAuth.config.allowed_request_methods = [ :post ]
  OmniAuth.config.silence_get_warning = true
  OmniAuth.config.on_failure = proc do |env|
    Account::OmniauthSessionsController.action(:failure).call(env)
  end
end
