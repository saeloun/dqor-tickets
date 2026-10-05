module NativeAttendeeBridgeHelpers
  CALLBACK = "https://deccanqueenonrails.com/native/attendee/synthetic-ios/callback"
  VERIFIER = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  STATE = "synthetic_native_state_1234567890123456789"

  def csrf_token(body = response.body, action: nil)
    document = Nokogiri::HTML(body)
    form = action ? document.at_css("form[action='#{action}']") : document.at_css("form")
    form&.at_css("input[name=authenticity_token]")&.[]("value")
  end

  def start_native_attempt(**overrides)
    get native_attendee_authorize_path, params: {
      client_id: "dqor-ios", redirect_uri: CALLBACK, state: STATE,
      code_challenge_method: "S256", code_challenge: NativeAttendeeAuthorization.challenge(VERIFIER)
    }.merge(overrides)
    expect(response).to have_http_status(:ok)
    NativeAttendeeAuthorization.order(:id).last
  end

  def send_native_link(email = user.email)
    perform_enqueued_jobs(only: NativeAttendeeVerificationJob) do
      post native_attendee_email_path, params: { email: email, authenticity_token: csrf_token(action: native_attendee_email_path) }
    end
    expect(response).to have_http_status(:accepted)
    ActionMailer::Base.deliveries.last
  end

  def native_verification_path(mail)
    body = mail.text_part ? mail.text_part.body.decoded : mail.body.decoded
    url = URI.parse(body.lines.find { |line| line.start_with?("http") }.strip)
    expect(url.scheme).to eq("https")
    expect(url.host).to eq(NativeAttendee::Clients::HOST)
    url.request_uri
  end

  def native_code
    start_native_attempt
    mail = send_native_link
    get native_verification_path(mail)
    expect(response).to redirect_to(native_attendee_consent_path)
    get native_attendee_consent_path
    expect(response).to have_http_status(:ok)
    @native_consent_token = csrf_token(action: native_attendee_consent_path)
    @native_cancel_token = csrf_token(action: native_attendee_cancel_path)
    post native_attendee_consent_path, params: { authenticity_token: @native_consent_token }
    expect(response).to have_http_status(:see_other)
    Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")
  end

  def exchange_native(code = native_code, **overrides)
    post "/api/native/attendee/v1/token", params: {
      code: code, code_verifier: VERIFIER, client_id: "dqor-ios", redirect_uri: CALLBACK
    }.merge(overrides), as: :json
  end

  def native_token
    exchange_native
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch("access_token")
  end

  def native_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def expect_native_private(status)
    expect(response).to have_http_status(status)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    path = ActionDispatch::Journey::Router::Utils.normalize_path(request.path)
    policy = path.start_with?("/account/native/") ? "strict-origin" : "no-referrer"
    expect(response.headers["Referrer-Policy"]).to eq(policy)
    expect(response.headers["ETag"]).to be_nil
    expect(response.headers["Last-Modified"]).to be_nil
  end
end

RSpec.configure do |config|
  config.include NativeAttendeeBridgeHelpers, :native_attendee_bridge
  config.around(:each, :native_attendee_bridge) do |example|
    original_flag = ENV["NATIVE_ATTENDEE_SESSION_API_ENABLED"]
    original_callbacks = ENV["NATIVE_ATTENDEE_CLIENT_CALLBACKS"]
    original_csrf = Account::Native::AuthorizationsController.allow_forgery_protection
    ENV["NATIVE_ATTENDEE_SESSION_API_ENABLED"] = "true"
    ENV["NATIVE_ATTENDEE_CLIENT_CALLBACKS"] = {
      "dqor-ios" => NativeAttendeeBridgeHelpers::CALLBACK,
      "dqor-android" => "https://deccanqueenonrails.com/native/attendee/synthetic-android/callback"
    }.to_json
    Account::Native::AuthorizationsController.allow_forgery_protection = true
    example.run
  ensure
    ENV["NATIVE_ATTENDEE_SESSION_API_ENABLED"] = original_flag
    ENV["NATIVE_ATTENDEE_CLIENT_CALLBACKS"] = original_callbacks
    Account::Native::AuthorizationsController.allow_forgery_protection = original_csrf
  end
end
