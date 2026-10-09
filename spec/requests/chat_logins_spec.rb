require "rails_helper"

RSpec.describe "Conference chat DQOR login", type: :request do
  let(:state) { "n" * 32 }

  before { OmniAuth.config.test_mode = true }
  after do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  around(:each, :csrf) do |example|
    google_client_id = ENV["GOOGLE_CLIENT_ID"]
    ENV["GOOGLE_CLIENT_ID"] = "test-client"
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
    google_client_id ? ENV["GOOGLE_CLIENT_ID"] = google_client_id : ENV.delete("GOOGLE_CLIENT_ID")
  end

  def google_callback(verified: true)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "g-chat", info: { email: " Verified@Example.com ", name: "Ruby Fan" },
      extra: { raw_info: { email_verified: verified } }
    )
    get "/auth/google_oauth2/callback"
  end

  def issue_code
    get chat_login_path, params: { state: state }
    google_callback
    follow_redirect!
    location = URI.parse(response.location)
    expect("#{location.scheme}://#{location.host}#{location.path}").to eq("https://chat.deccanqueenonrails.com/session/google/callback")
    Rack::Utils.parse_query(location.query).fetch("login_code")
  end

  it "reuses an existing verified DQOR session" do
    user = User.create!(email: "existing@example.com")
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
    get chat_login_path, params: { state: state }

    expect(response.location).to start_with("https://chat.deccanqueenonrails.com/session/google/callback?")
    expect(ChatLoginGrant.sole.email).to eq("existing@example.com")
    expect(response.headers["Cache-Control"]).to eq("no-store")
  end

  it "uses DQOR's existing sign-in page for a signed-out visitor", :csrf do
    get chat_login_path, params: { state: state }
    expect(response).to redirect_to(account_sign_in_path)
    follow_redirect!

    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('form[action="/account/sign_in"]')).to be_present
    form = doc.at_css('form[action="/auth/google_oauth2"]')
    expect(form["method"]).to eq("post")
    expect(form.at_css('input[name="authenticity_token"]')["value"]).to be_present
  end

  it "returns a verified email-link sign-in to Campfire after DQOR resets the session" do
    user = User.create!(email: "sonam@example.com", name: "Sonam")
    get chat_login_path, params: { state: state }
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)

    expect(response).to redirect_to(chat_login_path(state: state))
    follow_redirect!
    expect(ChatLoginGrant.sole.email).to eq(user.email)
    get account_root_path
    expect(response).to have_http_status(:ok)
  end

  it "reuses a verified Google DQOR session without granting email-link proof" do
    google_callback
    get chat_login_path, params: { state: state }

    expect(response.location).to start_with("https://chat.deccanqueenonrails.com/session/google/callback?")
    expect(ChatLoginGrant.sole.email).to eq("verified@example.com")
  end

  it "does not reuse a DQOR session without verified email evidence" do
    google_callback(verified: false)
    get chat_login_path, params: { state: state }

    expect(response).to redirect_to(account_sign_in_path)
    expect(ChatLoginGrant.count).to eq(0)
  end

  it "denies chat to a pilot-only identity even with a verified DQOR session" do
    user = User.create!(email: "pilot@example.com", free_pilot_identity: true)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
    get chat_login_path, params: { state: state }

    expect(response).to redirect_to(account_root_path)
    expect(ChatLoginGrant.count).to eq(0)
  end

  it "rejects malformed state before initiating Google authentication" do
    get chat_login_path, params: { state: "https://evil.example" }

    expect(response).to have_http_status(:bad_request)
  end

  it "redeems a hashed grant once for the freshly verified Google identity", :csrf do
    code = issue_code
    grant = ChatLoginGrant.sole
    expect(grant.code_digest).to eq(Digest::SHA256.hexdigest(code))
    expect(grant.expires_at).to be_within(1.second).of(60.seconds.from_now)

    previous_cookies = cookies.to_hash.dup
    post redeem_chat_login_path, params: { login_code: code, state: state }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("verified" => true, "email" => "verified@example.com", "name" => "Ruby Fan")
    expect(ChatLoginGrant.count).to eq(0)
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.headers["Set-Cookie"]).to be_nil
    expect(cookies.to_hash).to eq(previous_cookies)

    post redeem_chat_login_path, params: { login_code: code, state: state }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects missing grant credentials even with a signed-in DQOR cookie", :csrf do
    user = User.create!(email: "existing@example.com")
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
    previous_cookies = cookies.to_hash.dup

    post redeem_chat_login_path, params: {}, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["Set-Cookie"]).to be_nil
    expect(cookies.to_hash).to eq(previous_cookies)
  end

  it "rejects a mismatched state without consuming the valid grant" do
    code = issue_code
    post redeem_chat_login_path, params: { login_code: code, state: "x" * 32 }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(ChatLoginGrant.count).to eq(1)

    post redeem_chat_login_path, params: { login_code: code, state: state }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it "rejects expired or unknown codes" do
    code = issue_code
    travel 61.seconds do
      post redeem_chat_login_path, params: { login_code: code, state: state }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    post redeem_chat_login_path, params: { login_code: "x" * 43, state: state }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "requires the provider's boolean verified email claim for chat" do
    [ false, nil, "true" ].each do |verified|
      get chat_login_path, params: { state: state }
      expect { google_callback(verified: verified) }.not_to change(ChatLoginGrant, :count)
      expect(response).to redirect_to(account_sign_in_path)
    end
  end

  it "clears pending chat authentication after an OAuth failure" do
    get chat_login_path, params: { state: state }
    get "/auth/failure"
    google_callback

    expect(response).to redirect_to(account_root_path)
    expect(ChatLoginGrant.count).to eq(0)
  end

  it "filters grant codes, state and Google codes from parameter logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter("login_code" => "secret", "state" => state, "code" => "google-code").values).to eq([ "[FILTERED]" ] * 3)
  end
end
