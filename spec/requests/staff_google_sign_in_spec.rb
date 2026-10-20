require "rails_helper"

RSpec.describe "Staff Google sign-in", type: :request do
  around do |example|
    original_mode = OmniAuth.config.test_mode
    original_forgery = ActionController::Base.allow_forgery_protection
    original_credentials = ENV.values_at("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET")
    OmniAuth.config.test_mode = false
    ActionController::Base.allow_forgery_protection = true
    ENV["GOOGLE_CLIENT_ID"] = "test-client-id"
    ENV["GOOGLE_CLIENT_SECRET"] = "test-client-secret"
    example.run
  ensure
    OmniAuth.config.test_mode = original_mode
    ActionController::Base.allow_forgery_protection = original_forgery
    %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET].zip(original_credentials).each do |key, value|
      value ? ENV[key] = value : ENV.delete(key)
    end
  end

  def begin_google(staff: true)
    get(staff ? new_session_path : account_sign_in_path)
    action = staff ? "/auth/google_oauth2?login_context=staff" : "/auth/google_oauth2"
    form = Nokogiri::HTML(response.body).at_css("form[action='#{action}']")
    expect(form).to be_present
    post action, params: { authenticity_token: form.at_css("input[name='authenticity_token']")["value"] }
    expect(response.location).to start_with("https://accounts.google.com/")
    state = Rack::Utils.parse_query(URI.parse(response.location).query).fetch("state")
    expect(state).to be_present
    state
  end

  def stub_google(email:, verified: true)
    token = JWT.encode({ iss: "https://accounts.google.com", aud: "test-client-id", exp: 10.minutes.from_now.to_i }, "synthetic-jwt-key", "HS256")
    stub_request(:post, "https://oauth2.googleapis.com/token").to_return(
      headers: { "Content-Type" => "application/json" },
      body: { access_token: "synthetic-google-access-token", token_type: "Bearer", expires_in: 3600, id_token: token }.to_json)
    stub_request(:get, "https://www.googleapis.com/oauth2/v3/userinfo").to_return(
      headers: { "Content-Type" => "application/json" },
      body: { sub: "synthetic-google-staff", email:, email_verified: verified, name: "Synthetic Staff" }.to_json)
    stub_request(:post, "https://www.googleapis.com/oauth2/v3/tokeninfo").to_return(
      headers: { "Content-Type" => "application/json" }, body: { aud: "test-client-id", scope: "email profile" }.to_json)
  end

  def complete_google(state:, email:, verified: true, **params)
    stub_google(email:, verified:)
    get "/auth/google_oauth2/callback", params: { code: "synthetic-google-code", state:, **params }
  end

  def identity_counts
    [ AdminUser.count, User.count, Membership.count, ChatLoginGrant.count ]
  end

  %i[admin desk].each do |role|
    it "signs in an existing #{role} without changing identities, roles, or grants" do
      staff = create(:admin_user, role:, email: "#{role}@example.test")
      counts = identity_counts
      state = begin_google
      complete_google(state:, email: "  #{staff.email.upcase}  ")

      expect(response).to redirect_to(role == :desk ? "/checkin" : "/avo")
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(Session.sole.admin_user).to eq(staff)
      expect(staff.reload.role).to eq(role.to_s)
      expect(identity_counts).to eq(counts)
      expect(response.headers["Set-Cookie"].to_s.downcase).to include("httponly", "samesite=lax")
      get checkin_path
      expect(response).to have_http_status(:ok)
      get "/avo/dashboard"
      expect(response).to(role == :desk ? redirect_to("/checkin") : have_http_status(:ok))
    end
  end

  it "keeps an admin's originally requested protected path" do
    staff = create(:admin_user, email: "return@example.test")
    get checkin_path
    expect(response).to redirect_to(new_session_path)
    complete_google(state: begin_google, email: staff.email)
    expect(response).to redirect_to("/checkin")
  end

  it "does not grant staff access from an attendee Google request even when callback params claim staff" do
    staff = create(:admin_user, email: "same-address@example.test")
    complete_google(state: begin_google(staff: false), email: staff.email, login_context: "staff")
    expect(response).to redirect_to(account_root_path)
    expect(Session.count).to eq(0)
    expect(staff.reload.role).to eq("admin")
    get checkin_path
    expect(response).to redirect_to(new_session_path)
  end

  it "uses the original staff request context when callback params claim attendee" do
    staff = create(:admin_user, role: :desk)
    complete_google(state: begin_google, email: staff.email, login_context: "attendee")
    expect(response).to redirect_to("/checkin")
    expect(User.count).to eq(0)
    expect(Session.sole.admin_user).to eq(staff)
  end

  it "denies an unknown verified Google identity without provisioning any account" do
    state = begin_google
    counts = identity_counts
    complete_google(state:, email: "unknown@example.test")
    expect(response).to redirect_to(new_session_path)
    expect(identity_counts).to eq(counts)
    expect(Session.count).to eq(0)
  end

  it "denies an attendee organization owner without a matching staff account" do
    attendee = User.create!(email: "owner@example.test")
    organization = Organization.create!(name: "Synthetic organization", slug: "synthetic-google-owner")
    Membership.create!(organization:, user: attendee, role: :owner)
    state = begin_google
    counts = identity_counts
    complete_google(state:, email: attendee.email)
    expect(response).to redirect_to(new_session_path)
    expect(identity_counts).to eq(counts)
    expect(Session.count).to eq(0)
  end

  [ false, nil, "true", 1 ].each do |verification|
    it "rejects email verification #{verification.inspect} without falling through to attendee login" do
      staff = create(:admin_user)
      state = begin_google
      counts = identity_counts
      complete_google(state:, email: staff.email, verified: verification)
      expect(response).to redirect_to(new_session_path)
      expect(identity_counts).to eq(counts)
      expect(Session.count).to eq(0)
    end
  end

  [ nil, "", "invalid-address" ].each do |email|
    it "rejects Google email #{email.inspect} without creating identities" do
      state = begin_google
      counts = identity_counts
      complete_google(state:, email:)
      expect(response).to redirect_to(new_session_path)
      expect(identity_counts).to eq(counts)
      expect(Session.count).to eq(0)
    end
  end

  it "denies a staff account deleted during the OAuth round trip" do
    staff = create(:admin_user)
    email = staff.email
    state = begin_google
    staff.destroy!
    complete_google(state:, email:)
    expect(response).to redirect_to(new_session_path)
    expect(identity_counts).to eq([ 0, 0, 0, 0 ])
    expect(Session.count).to eq(0)
  end

  it "rechecks an email changed between lookup and the locked session issuance" do
    staff = create(:admin_user)
    email = staff.email
    state = begin_google
    allow(AdminUser).to receive(:find_by).and_call_original
    allow(AdminUser).to receive(:find_by).with(email:).and_wrap_original do |method, **arguments|
      found = method.call(**arguments)
      AdminUser.where(id: staff.id).update_all(email: "changed-staff@example.test")
      found
    end
    complete_google(state:, email:)
    expect(response).to redirect_to(new_session_path)
    expect(Session.count).to eq(0)
    expect(User.count).to eq(0)
  end

  it "rechecks a downgraded admin role before issuing its session" do
    staff = create(:admin_user, role: :admin)
    state = begin_google
    staff.update!(role: :desk)
    complete_google(state:, email: staff.email)
    expect(response).to redirect_to("/checkin")
    get "/avo/dashboard"
    expect(response).to redirect_to("/checkin")
    expect(staff.reload.role).to eq("desk")
  end

  it "denies an account whose current role is not admin or desk" do
    staff = create(:admin_user)
    state = begin_google
    AdminUser.where(id: staff.id).update_all(role: 99)
    complete_google(state:, email: staff.email)
    expect(response).to redirect_to(new_session_path)
    expect(Session.count).to eq(0)
    expect(User.count).to eq(0)
  end

  it "rejects a POST without CSRF proof and never contacts the token endpoint" do
    get new_session_path
    post "/auth/google_oauth2?login_context=staff"
    expect(response).to have_http_status(:unprocessable_content)
    expect(Session.count).to eq(0)
    expect(User.count).to eq(0)
  end

  it "cannot change a pending attendee login into staff intent with an invalid CSRF POST" do
    staff = create(:admin_user)
    state = begin_google(staff: false)
    post "/auth/google_oauth2?login_context=staff"
    expect(response).to have_http_status(:unprocessable_content)
    complete_google(state:, email: staff.email)
    expect(response).to redirect_to(account_root_path)
    expect(Session.count).to eq(0)
    expect(User.sole.email).to eq(staff.email)
    expect(WebMock).to have_requested(:post, "https://oauth2.googleapis.com/token").once
  end

  it "does not start Google authentication over GET" do
    get "/auth/google_oauth2", params: { login_context: "staff" }
    expect(response).to have_http_status(:not_found)
    expect(Session.count).to eq(0)
  end

  [ "", "tampered-state" ].each do |state|
    it "rejects callback state #{state.inspect} and consumes the pending staff intent" do
      staff = create(:admin_user)
      valid_state = begin_google
      complete_google(state:, email: staff.email)
      expect(response).to redirect_to(new_session_path)
      complete_google(state: valid_state, email: staff.email)
      expect(Session.count).to eq(0)
      expect(User.count).to eq(0)
      expect(WebMock).not_to have_requested(:post, "https://oauth2.googleapis.com/token")
    end
  end

  it "does not issue another staff session when a successful callback is replayed" do
    staff = create(:admin_user)
    state = begin_google
    complete_google(state:, email: staff.email)
    expect(Session.count).to eq(1)
    complete_google(state:, email: staff.email)
    expect(Session.count).to eq(1)
    expect(User.count).to eq(0)
    expect(WebMock).to have_requested(:post, "https://oauth2.googleapis.com/token").once
  end

  it "returns canceled staff authentication to the staff password fallback" do
    state = begin_google
    get "/auth/google_oauth2/callback", params: { state:, error: "access_denied" }
    expect(response).to redirect_to(new_session_path)
    follow_redirect!
    expect(response.body).to include("Sign in", "password", "Continue with Google")
    expect(Session.count).to eq(0)
    expect(User.count).to eq(0)
  end

  it "revokes the Google-created staff session through existing logout" do
    staff = create(:admin_user)
    complete_google(state: begin_google, email: staff.email)
    get checkin_path
    token = Nokogiri::HTML(response.body).at_css("meta[name='csrf-token']")["content"]
    delete session_path, params: { authenticity_token: token }
    expect(Session.count).to eq(0)
    get checkin_path
    expect(response).to redirect_to(new_session_path)
  end

  it "hides Google when either configured credential is absent while retaining password login" do
    %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET].each do |missing|
      original = ENV.delete(missing)
      get new_session_path
      expect(Nokogiri::HTML(response.body).at_css("form[action='/auth/google_oauth2?login_context=staff']")).to be_nil
      expect(response.body).to include('type="password"', "Sign in")
      ENV[missing] = original
    end
  end
end
