require "rails_helper"

RSpec.describe "Native attendee PKCE bridge", type: :request, native_attendee_bridge: true do
  let(:user) { User.create!(email: "native-existing@example.test", name: "Synthetic native attendee") }

  before { ActionMailer::Base.deliveries.clear }

  it "executes fresh mail verification, explicit consent, PKCE exchange, own reads and server-confirmed logout" do
    ticket = create(:ticket, order: create(:order, :paid, expires_at: 1.hour.ago), attendee_email: user.email)
    token = native_token
    record = NativeAttendeeSession.last
    expect_native_private(:ok)
    expect(response.parsed_body.keys).to contain_exactly("access_token", "token_type", "expires_at", "event", "capabilities")
    expect(response.parsed_body).to include("token_type" => "Bearer", "event" => "dqor-2026", "capabilities" => %w[account:read passes:read])
    expect(record.expires_at).to be_within(2.seconds).of(30.minutes.from_now)
    expect(record.token_digest).to eq(Digest::SHA256.hexdigest(token))
    expect(record.attributes.values).not_to include(token)
    get "/api/native/attendee/v1/account", headers: native_headers(token)
    expect_native_private(:ok)
    expect(response.parsed_body.fetch("account")).to eq("id" => user.id.to_s, "name" => user.name, "email" => user.email)
    get "/api/native/attendee/v1/passes", headers: native_headers(token)
    expect_native_private(:ok)
    expect(response.parsed_body.fetch("passes").first).to include("id" => ticket.id.to_s, "status" => "confirmed")
    expect(response.body).not_to include(token, ticket.secret, ticket.claim_token, ticket.order.code, "price_paise", "buyer_phone")
    get "/api/native/attendee/v1/session", headers: native_headers(token)
    expect_native_private(:ok)
    expect(response.body).not_to include(token)
    delete "/api/native/attendee/v1/session", headers: native_headers(token)
    expect_native_private(:no_content)
    get "/api/native/attendee/v1/account", headers: native_headers(token)
    expect_native_private(:unauthorized)
    expect(record.reload.revoked_at).to be_present
  end

  it "fails closed when disabled, config missing/malformed or transport is production HTTP" do
    ENV.delete("NATIVE_ATTENDEE_SESSION_API_ENABLED")
    get "/api/native/attendee/v1/account"
    expect_native_private(:not_found)
    get native_attendee_authorize_path
    expect_native_private(:not_found)
    ENV["NATIVE_ATTENDEE_SESSION_API_ENABLED"] = "true"
    [ nil, "{}", "[]", "garbage", '{"unknown":"https://deccanqueenonrails.com/native/attendee/x"}' ].each do |mapping|
      ENV["NATIVE_ATTENDEE_CLIENT_CALLBACKS"] = mapping
      get "/api/native/attendee/v1/account"
      expect_native_private(:service_unavailable)
    end
    ENV["NATIVE_ATTENDEE_CLIENT_CALLBACKS"] = { "dqor-ios" => NativeAttendeeBridgeHelpers::CALLBACK }.to_json
    allow(Rails.env).to receive(:production?).and_return(true)
    get "/api/native/attendee/v1/account"
    expect_native_private(:forbidden)
  end

  it "requires exact approved client/callback and S256 rather than plain or return-to inputs" do
    inputs = [ { client_id: "unknown" }, { redirect_uri: NativeAttendeeBridgeHelpers::CALLBACK + "?x=1" }, { redirect_uri: "https://evil.example/callback" },
      { redirect_uri: NativeAttendeeBridgeHelpers::CALLBACK.sub("https", "http") }, { code_challenge_method: "plain" }, { state: "short" }, { code_challenge: "bad" } ]
    inputs.each do |override|
      get native_attendee_authorize_path, params: { client_id: "dqor-ios", redirect_uri: NativeAttendeeBridgeHelpers::CALLBACK, state: NativeAttendeeBridgeHelpers::STATE,
        code_challenge: NativeAttendeeAuthorization.challenge(NativeAttendeeBridgeHelpers::VERIFIER), code_challenge_method: "S256" }.merge(override)
      expect_native_private(:conflict)
    end
    expect(NativeAttendeeAuthorization.count).to eq(0)
    start_native_attempt(return_to: "https://evil.example")
    expect(response.body).not_to include("evil.example")
  end

  it "does not authorize from an ordinary verified cookie or a staff token/cookie" do
    magic = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: magic)
    get "/api/native/attendee/v1/account"
    expect_native_private(:unauthorized)
    start_native_attempt
    get native_attendee_consent_path
    expect_native_private(:conflict)
    sign_in_admin
    get "/api/native/attendee/v1/passes"
    expect_native_private(:unauthorized)
    allow(NativeStaffSession).to receive(:enabled?).and_return(true)
    allow(NativeStaffSession).to receive(:configured_dates).and_return([ "2026-10-08" ])
    operator = create(:admin_user, role: :desk)
    post "/api/staff/session", params: { email: operator.email, password: "password123" }, as: :json
    staff_token = response.parsed_body.fetch("access_token")
    get "/api/native/attendee/v1/account", headers: native_headers(staff_token)
    expect_native_private(:unauthorized)
  end

  it "never provisions an account and makes unknown-email responses indistinguishable" do
    user
    start_native_attempt
    known_response = nil
    expect { send_native_link }.not_to change(User, :count)
    known_response = response.body
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    start_native_attempt(state: "different_native_state_1234567890123456789")
    expect { send_native_link("missing@example.test") }.not_to change(User, :count)
    expect(response.body).to eq(known_response)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(NativeAttendeeSession.count).to eq(0)
  end

  it "supports a different browser opening the native-specific email without copying login cookies" do
    attempt = start_native_attempt
    mail = send_native_link
    browser = ActionDispatch::Integration::Session.new(Rails.application)
    browser.get(native_verification_path(mail))
    expect(browser.response.status).to eq(302)
    expect(URI.parse(browser.response.location).path).to eq(native_attendee_consent_path)
    browser.get(native_attendee_consent_path)
    expect(browser.response.body).to include(user.email, "Approve account and pass reads")
    browser.post(native_attendee_consent_path, params: { authenticity_token: csrf_token(browser.response.body, action: native_attendee_consent_path) })
    expect(browser.response).to have_http_status(:see_other)
    expect(attempt.reload).to be_issued
    expect(NativeAttendeeSession.count).to eq(0)
    get native_attendee_consent_path
    expect_native_private(:conflict)
  end

  it "requires CSRF protection on email, consent and cancel, while GET scanners mint no session" do
    attempt = start_native_attempt
    post native_attendee_email_path, params: { email: user.email }
    expect_native_private(:forbidden)
    expect(enqueued_jobs).to be_empty
    get native_attendee_authorize_path, params: { client_id: "dqor-ios", redirect_uri: NativeAttendeeBridgeHelpers::CALLBACK, state: NativeAttendeeBridgeHelpers::STATE,
      code_challenge: NativeAttendeeAuthorization.challenge(NativeAttendeeBridgeHelpers::VERIFIER), code_challenge_method: "S256" }
    mail = send_native_link
    get native_verification_path(mail)
    get native_attendee_consent_path
    expect_native_private(:ok)
    expect(NativeAttendeeSession.count).to eq(0)
    expect(NativeAttendeeAuthorization.last.code_digest).to be_nil
    post native_attendee_consent_path
    expect_native_private(:forbidden)
    post native_attendee_cancel_path
    expect_native_private(:forbidden)
    expect(attempt.reload).to be_pending
    expect(NativeAttendeeSession.count).to eq(0)
  end

  it "uses strict-origin browser forms and retains normal Rails origin and CSRF enforcement" do
    [ "null", "https://evil.example" ].each do |origin|
      start_native_attempt
      token = csrf_token(action: native_attendee_email_path)
      post native_attendee_email_path, params: { email: user.email, authenticity_token: token }, headers: { "Origin" => origin, "Sec-Fetch-Site" => "same-origin" }
      expect_native_private(:forbidden)
    end
    start_native_attempt
    expect(response.body).to include('name="referrer" content="strict-origin"')
    token = csrf_token(action: native_attendee_email_path)
    headers = { "Origin" => "http://www.example.com" }
    post native_attendee_email_path, params: { email: user.email }, headers: headers
    expect_native_private(:forbidden)
    post native_attendee_email_path, params: { email: user.email, authenticity_token: token }, headers: headers
    expect_native_private(:accepted)
  end

  it "rejects tampered/ordinary verification links and email changes before fresh proof" do
    attempt = start_native_attempt
    mail = send_native_link
    ordinary = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get native_attendee_verify_path(token: ordinary)
    expect_native_private(:conflict)
    get native_attendee_verify_path(token: "tampered")
    expect_native_private(:conflict)
    user.update!(email: "changed-before@example.test")
    get native_verification_path(mail)
    expect_native_private(:conflict)
    expect(attempt.reload).to be_canceled
  end

  it "invalidates the attempt when a password changes after verification and before consent" do
    attempt = start_native_attempt
    mail = send_native_link
    get native_verification_path(mail)
    get native_attendee_consent_path
    consent = csrf_token(action: native_attendee_consent_path)
    fingerprint = attempt.reload.password_fingerprint
    user.update!(password: "synthetic-new-password")
    post native_attendee_consent_path, params: { authenticity_token: consent }
    expect_native_private(:conflict)
    expect(attempt.reload.password_fingerprint).to eq(fingerprint)
    expect(attempt).to be_canceled
    expect(NativeAttendeeSession.count).to eq(0)
  end

  it "rechecks password/email at exchange and returns the same generic invalid grant" do
    code = native_code
    user.update!(password: "changed-at-exchange")
    exchange_native(code)
    expect_native_private(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq("invalid_grant")
    expect(NativeAttendeeAuthorization.last).to be_canceled
    expect(NativeAttendeeSession.count).to eq(0)
  end

  it "rejects wrong PKCE/client/callback, code replay and repeated verification/consent" do
    code = native_code
    [ { code_verifier: nil }, { code_verifier: "x" * 43 }, { client_id: "dqor-android" }, { redirect_uri: NativeAttendeeBridgeHelpers::CALLBACK + "/wrong" } ].each do |override|
      exchange_native(code, **override)
      expect_native_private(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_grant")
    end
    exchange_native(code)
    expect_native_private(:ok)
    exchange_native(code)
    expect_native_private(:too_many_requests)
    get native_verification_path(ActionMailer::Base.deliveries.last)
    expect_native_private(:conflict)
    get native_attendee_consent_path
    expect_native_private(:conflict)
    expect(NativeAttendeeSession.count).to eq(1)
  end

  it "immediately rejects consumed-code replay independently of rate limits" do
    code = native_code
    exchange_native(code)
    expect_native_private(:ok)
    exchange_native(code)
    expect_native_private(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq("invalid_grant")
    expect(NativeAttendeeSession.count).to eq(1)
  end

  it "cannot replace a code through repeated valid consent" do
    code = native_code
    attempt = NativeAttendeeAuthorization.last
    original_digest = attempt.code_digest
    post native_attendee_consent_path, params: { authenticity_token: @native_consent_token }
    expect_native_private(:conflict)
    expect(attempt.reload.code_digest).to eq(original_digest)
    exchange_native(code)
    expect_native_private(:ok)
    expect(NativeAttendeeSession.count).to eq(1)
  end

  it "persists expired attempts after a locked request and rejects changed email at consent and exchange" do
    attempt = start_native_attempt
    token = csrf_token(action: native_attendee_email_path)
    travel 10.minutes + 1.second do
      post native_attendee_email_path, params: { email: user.email, authenticity_token: token }
      expect_native_private(:conflict)
    end
    expect(attempt.reload).to be_expired
    code = native_code
    user.update!(email: "changed-exchange-email@example.test")
    exchange_native(code)
    expect_native_private(:unauthorized)
    expect(NativeAttendeeAuthorization.last).to be_canceled
    start_native_attempt
    mail = send_native_link
    get native_verification_path(mail)
    get native_attendee_consent_path
    token = csrf_token(action: native_attendee_consent_path)
    user.update!(email: "changed-consent-email@example.test")
    post native_attendee_consent_path, params: { authenticity_token: token }
    expect_native_private(:conflict)
    expect(NativeAttendeeAuthorization.last).to be_canceled
  end

  it "expires ten-minute attempts, sixty-second codes and thirty-minute sessions without refresh" do
    attempt = start_native_attempt
    mail = send_native_link
    travel 10.minutes + 1.second do
      get native_verification_path(mail)
      expect_native_private(:conflict)
    end
    expect(attempt.reload).to be_pending
    code = native_code
    travel 61.seconds do
      exchange_native(code)
      expect_native_private(:unauthorized)
    end
    expect(NativeAttendeeSession.count).to eq(0)
    expect(NativeAttendeeAuthorization.last).to be_expired
    token = native_token
    expiry = NativeAttendeeSession.last.expires_at
    get "/api/native/attendee/v1/session", headers: native_headers(token)
    expect(NativeAttendeeSession.last.expires_at).to eq(expiry)
    travel 30.minutes + 1.second do
      get "/api/native/attendee/v1/session", headers: native_headers(token)
      expect_native_private(:unauthorized)
    end
    expect(response.body).not_to include("refresh_token")
  end

  it "makes canceled attempts terminal and cannot revoke a consumed attempt through browser cancel" do
    attempt = start_native_attempt
    post native_attendee_cancel_path, params: { authenticity_token: csrf_token(action: native_attendee_cancel_path) }
    expect_native_private(:ok)
    expect(attempt.reload).to be_canceled
    get native_attendee_consent_path
    expect_native_private(:conflict)
    code = native_code
    cancel_token = @native_cancel_token
    exchange_native(code)
    token = response.parsed_body.fetch("access_token")
    post native_attendee_cancel_path, params: { authenticity_token: cancel_token }
    expect_native_private(:conflict)
    get "/api/native/attendee/v1/session", headers: native_headers(token)
    expect_native_private(:ok)
    expect(NativeAttendeeSession.count).to eq(1)
  end

  it "revokes on current email/password changes and fails closed for a deleted User" do
    token = native_token
    user.update!(email: "changed-session@example.test")
    get "/api/native/attendee/v1/account", headers: native_headers(token)
    expect_native_private(:unauthorized)
    expect(NativeAttendeeSession.last.revoked_at).to be_present
    user.update!(email: "native-existing@example.test")
    get "/api/native/attendee/v1/account", headers: native_headers(token)
    expect_native_private(:unauthorized)
    token = native_token
    user.update!(password: "changed-session-password")
    get "/api/native/attendee/v1/session", headers: native_headers(token)
    expect_native_private(:unauthorized)
    token = native_token
    user.destroy!
    get "/api/native/attendee/v1/session", headers: native_headers(token)
    expect_native_private(:unauthorized)
    expect(NativeAttendeeSession.count).to eq(0)
  end

  it "preserves private snapshots, assigned-email ownership and live pass state in the new namespace" do
    own = create(:ticket, order: create(:order, :paid), attendee_email: user.email)
    buyer = create(:order, :paid, email: user.email)
    create(:ticket, order: buyer, attendee_email: "another@example.test")
    token = native_token
    travel_to Time.current.change(usec: 0) do
      get "/api/native/attendee/v1/passes", headers: native_headers(token)
      expect_native_private(:ok)
      expect(response.parsed_body.fetch("passes").pluck("id")).to eq([ own.id.to_s ])
      snapshot = response.body
      get "/api/native/attendee/v1/passes", headers: native_headers(token).merge("If-None-Match" => %(W/"#{Digest::SHA256.hexdigest(snapshot).byteslice(0, 32)}"))
      expect_native_private(:ok)
      expect(response.body).to eq(snapshot)
    end
    own.update!(canceled_at: Time.current)
    get "/api/native/attendee/v1/passes", headers: native_headers(token)
    expect(response.parsed_body.fetch("passes").first.fetch("status")).to eq("canceled")
    own.update!(attendee_email: "reassigned@example.test")
    get "/api/native/attendee/v1/passes", headers: native_headers(token)
    expect(response.parsed_body.fetch("passes")).to be_empty
    get "/api/native/attendee/v1/passes", params: { cursor: "01" }, headers: native_headers(token)
    expect_native_private(:unprocessable_content)
    get "/api/attendee/v1/account", headers: native_headers(token)
    expect_native_private(:not_found)
  end

  it "requires JSON body exchange, never exposes callback code in the browser fallback, and issues no token on GET" do
    code = native_code
    location = response.location
    get URI.parse(location).request_uri
    expect_native_private(:gone)
    expect(response.body).not_to include(code, NativeAttendeeBridgeHelpers::STATE, "script", "img")
    post "/api/native/attendee/v1/token", params: { code: code, code_verifier: NativeAttendeeBridgeHelpers::VERIFIER, client_id: "dqor-ios", redirect_uri: NativeAttendeeBridgeHelpers::CALLBACK }
    expect_native_private(:bad_request)
    get "/api/native/attendee/v1/token"
    expect(NativeAttendeeSession.count).to eq(0)
  end

  it "fails closed on unavailable rate counts before enqueueing mail or exchanging" do
    start_native_attempt
    allow(Rails.cache).to receive(:increment).and_return(nil)
    post native_attendee_email_path, params: { email: user.email, authenticity_token: csrf_token(action: native_attendee_email_path) }
    expect_native_private(:service_unavailable)
    expect(enqueued_jobs).to be_empty
    expect(NativeAttendeeSession.count).to eq(0)
    allow(Rails.cache).to receive(:increment).and_raise(IOError, "synthetic cache failure")
    post "/api/native/attendee/v1/token", params: {}, as: :json
    expect_native_private(:service_unavailable)
  end

  it "rejects ambiguous exchange fields and noncanonical bearer credentials without cookie fallback" do
    code = native_code
    exchange_native(code, refresh_token: "synthetic-extra-field")
    expect_native_private(:bad_request)
    expect(NativeAttendeeSession.count).to eq(0)
    exchange_native(code)
    token = response.parsed_body.fetch("access_token")
    [ token, "bearer #{token}", "Bearer  #{token}", "Bearer #{token} ", "Bearer #{token},other", "Bearer #{token}\n" ].each do |header|
      get "/api/native/attendee/v1/account", headers: { "Authorization" => header }
      expect_native_private(:unauthorized)
    end
    get "/api/native/attendee/v1/account", params: { token: token }
    expect_native_private(:unauthorized)
    get "/api/native/attendee/v1/account", headers: native_headers(token)
    expect_native_private(:ok)
  end

  it "authenticates nil-password email identities and revokes a nil-to-password transition" do
    expect(user.password_digest).to be_nil
    token = native_token
    expect(NativeAttendeeSession.last.password_fingerprint).to eq(Digest::SHA256.hexdigest(""))
    user.update!(password: "synthetic-established-password")
    get "/api/native/attendee/v1/account", headers: native_headers(token)
    expect_native_private(:unauthorized)
    expect(NativeAttendeeSession.last.revoked_at).to be_present
  end

  it "uses bounded hashed send limits identically for known and unknown emails" do
    [ user.email, "unknown-limit@example.test" ].each do |email|
      4.times do |index|
        start_native_attempt
        post native_attendee_email_path, params: { email: email, authenticity_token: csrf_token(action: native_attendee_email_path) }
        expect_native_private(index < 3 ? :accepted : :too_many_requests)
      end
    end
    expect(response.headers["Retry-After"]).to eq("180")
    expect(User.where(email: "unknown-limit@example.test")).not_to exist
  end
end
