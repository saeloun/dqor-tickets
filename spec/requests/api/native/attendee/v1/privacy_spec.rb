require "rails_helper"

RSpec.describe "Native attendee flow privacy", type: :request, native_attendee_bridge: true do
  let(:user) { User.create!(email: "native-privacy@example.test", name: "Synthetic privacy attendee") }

  it "redacts actual request, redirect, SQL and safe email-job logs without credential arguments" do
    output = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output))
    logger.level = Logger::DEBUG
    previous = [ Rails.logger, ActionController::Base.logger, ActiveRecord::Base.logger, ActiveJob::Base.logger, ActionMailer::Base.logger ]
    Rails.logger = ActionController::Base.logger = ActiveRecord::Base.logger = ActiveJob::Base.logger = ActionMailer::Base.logger = logger
    code = native_code
    body = ActionMailer::Base.deliveries.last.body.decoded
    verification = Rack::Utils.parse_query(URI.parse(body.lines.find { |line| line.start_with?("http") }.strip).query).fetch("token")
    exchange_native(code)
    token = response.parsed_body.fetch("access_token")
    get "/api/native/attendee/v1/account", headers: native_headers(token)
    get NativeAttendeeBridgeHelpers::CALLBACK.delete_prefix("https://deccanqueenonrails.com"), params: { code: code, state: NativeAttendeeBridgeHelpers::STATE }
    expect_native_private(:gone)
    post "/api/native/attendee/v1/token", params: '{"code_verifier":"SYNTHETIC_MALFORMED_JSON_SECRET"', headers: { "CONTENT_TYPE" => "application/json" }, env: { "action_dispatch.logger" => logger }
    expect_native_private(:bad_request)
    logs = output.string
    expect(logs).to include("Started", "[FILTERED]", "NativeAttendeeVerificationJob")
    expect(logs).not_to include(code, token, verification, NativeAttendeeBridgeHelpers::VERIFIER, NativeAttendeeBridgeHelpers::STATE,
      NativeAttendeeAuthorization.challenge(NativeAttendeeBridgeHelpers::VERIFIER), "SYNTHETIC_MALFORMED_JSON_SECRET")
    expect(NativeAttendeeVerificationJob.log_arguments).to be(false)
    expect(NativeAttendeeMailDeliveryJob.log_arguments).to be(false)
    expect(enqueued_jobs.any? { |job| job[:args].to_s.include?(verification) }).to be(false)
  ensure
    Rails.logger, ActionController::Base.logger, ActiveRecord::Base.logger, ActiveJob::Base.logger, ActionMailer::Base.logger = previous if previous
  end

  it "redacts malformed JSON through the boot-installed request logger and keeps unrelated logging intact" do
    file = Rails.root.join("log/test.log")
    offset = file.size
    sentinel = "SYNTHETIC_BOOT_PARSE_SECRET_#{SecureRandom.hex(8)}"
    [ "/api/native/attendee/v1/token", "/api//native/attendee/v1/token" ].each do |path|
      post path, params: %({"code_verifier":"#{sentinel}"), headers: { "CONTENT_TYPE" => "application/json" }
      expect_native_private(:bad_request)
    end
    log = file.binread.byteslice(offset..)
    expect(log).to include("Error occurred while parsing native request parameters. [FILTERED]")
    expect(log).not_to include(sentinel)
    get "/native//attendee/synthetic-ios/callback", params: { code: sentinel }
    expect_native_private(:gone)
    expect(response.body).not_to include(sentinel)
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    logger.level = Logger::DEBUG
    middleware = NativeAttendee::RequestPrivacy.new(->(env) { env.fetch("action_dispatch.logger").debug("PUBLIC_LOG_PRESERVED"); [ 200, {}, [] ] })
    middleware.call("PATH_INFO" => "/tickets", "action_dispatch.logger" => logger)
    expect(output.string).to include("PUBLIC_LOG_PRESERVED")
  end

  it "stops disabled new paths before parsing, database/cache authorization or jobs" do
    ENV.delete("NATIVE_ATTENDEE_SESSION_API_ENABLED")
    expect(NativeAttendeeAuthorization).not_to receive(:find_by)
    expect(NativeAttendeeSession).not_to receive(:find_by)
    expect(NativeAttendee::RateLimit).not_to receive(:check!)
    expect(NativeAttendeeVerificationJob).not_to receive(:perform_later)
    [ native_attendee_email_path, "/api/native/attendee/v1/token", "/native/attendee/synthetic-ios/callback",
      "/account//native/email", "/api//native/attendee/v1/token", "/native//attendee/synthetic-ios/callback" ].each do |path|
      post path, params: '{"code":"SYNTHETIC_DISABLED_BODY_SECRET"', headers: { "CONTENT_TYPE" => "application/json" }
      expect_native_private(:not_found)
      expect(response.parsed_body).to eq("schema_version" => 1, "error" => { "code" => "not_found" })
    end
  end

  it "suppresses only positively identified native-flow telemetry and preserves public or malformed unrelated events" do
    event = Struct.new(:request).new(Struct.new(:url).new("https://deccanqueenonrails.com/account/native/verify?token=SYNTHETIC_TELEMETRY_SECRET"))
    expect(NativeAttendee::RequestPrivacy.filter_event(event)).to be_nil
    event.request.url = "https://deccanqueenonrails.com/account//native/verify?token=SYNTHETIC_TELEMETRY_SECRET"
    expect(NativeAttendee::RequestPrivacy.filter_event(event)).to be_nil
    event.request.url = "https://deccanqueenonrails.com/tickets?public=true"
    expect(NativeAttendee::RequestPrivacy.filter_event(event)).to equal(event)
    event.request.url = "http://[malformed-public-url"
    expect(NativeAttendee::RequestPrivacy.filter_event(event)).to equal(event)
    event.request = nil
    expect(NativeAttendee::RequestPrivacy.filter_event(event)).to equal(event)
  end

  it "drops actual new-flow events and secret breadcrumbs through Sentry's local dummy transport" do
    Sentry.init do |configuration|
      configuration.dsn = "https://synthetic@telemetry.example.test/1"
      configuration.transport.transport_class = Sentry::DummyTransport
      configuration.background_worker_threads = 0
      configuration.environment = "test"
      configuration.enabled_environments = [ "test" ]
      configuration.traces_sample_rate = 1.0
      NativeAttendee::RequestPrivacy.install_filters(configuration)
    end
    subscriber = ActiveSupport::Notifications.subscribe("start_processing.action_controller") do |_name, _start, _finish, _id, payload|
      if [ "Account::Native::AuthorizationsController", "Api::Native::Attendee::V1::TokensController" ].include?(payload[:controller])
        Sentry.add_breadcrumb(Sentry::Breadcrumb.new(message: "SYNTHETIC_NATIVE_BREADCRUMB_SECRET"))
        Sentry.capture_message("SYNTHETIC_NATIVE_EVENT_SECRET")
        Sentry.start_transaction(name: "SYNTHETIC_NATIVE_TRANSACTION_SECRET", op: "http", sampled: true).finish
      end
    end
    transport = Sentry.get_current_client.transport
    get "/"
    Sentry.capture_message("PUBLIC_BEFORE_FLOW")
    expect(transport.events.size + transport.envelopes.size).to be >= 1
    transport.clear
    get "/account//native/authorize", params: { client_id: "dqor-ios", redirect_uri: NativeAttendeeBridgeHelpers::CALLBACK, state: NativeAttendeeBridgeHelpers::STATE,
      code_challenge: NativeAttendeeAuthorization.challenge(NativeAttendeeBridgeHelpers::VERIFIER), code_challenge_method: "S256" }
    expect_native_private(:ok)
    post "/api//native/attendee/v1/token", params: '{"code_verifier":"SYNTHETIC_TELEMETRY_BODY_SECRET"', headers: { "CONTENT_TYPE" => "application/json" }
    expect_native_private(:bad_request)
    expect(transport.events.map { |event| [ event.message, URI.parse(event.request&.url.to_s).path ] }).to be_empty
    expect(transport.envelopes).to be_empty
    expect(Sentry.get_current_scope.breadcrumbs.members.map(&:message)).not_to include("SYNTHETIC_NATIVE_BREADCRUMB_SECRET")
    get "/"
    Sentry.capture_message("PUBLIC_EVENT_PRESERVED")
    Sentry.start_transaction(name: "PUBLIC_TRANSACTION_PRESERVED", op: "http", sampled: true).finish
    expect(transport.events.size + transport.envelopes.size).to be >= 2
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    Sentry.close if Sentry.initialized?
  end

  it "keeps new HTML pages asset-free and private, including invalid routes" do
    start_native_attempt
    expect_native_private(:ok)
    expect(response.body).not_to include("<script", "<link", "<iframe", "<img", "serviceWorker", "analytics")
    expect(response.headers["Content-Security-Policy"]).to include("default-src 'none'", "form-action 'self'")
    html = response.body
    get native_attendee_authorize_path, params: { client_id: "dqor-ios", redirect_uri: NativeAttendeeBridgeHelpers::CALLBACK, state: NativeAttendeeBridgeHelpers::STATE,
      code_challenge: NativeAttendeeAuthorization.challenge(NativeAttendeeBridgeHelpers::VERIFIER), code_challenge_method: "S256" },
      headers: { "If-None-Match" => %(W/"#{Digest::SHA256.hexdigest(html).byteslice(0, 32)}") }
    expect_native_private(:ok)
    get "/api/native/attendee/v1/not-an-endpoint", params: { code_verifier: "SYNTHETIC_PRIVATE_VALUE" }
    expect_native_private(:not_found)
  end

  it "accepts only exact HTTPS callback configuration and no wildcard, aliases or duplicate targets" do
    invalid = [ NativeAttendeeBridgeHelpers::CALLBACK + "?code=x", NativeAttendeeBridgeHelpers::CALLBACK + "#fragment",
      NativeAttendeeBridgeHelpers::CALLBACK.sub(".com/", ".com:444/"), NativeAttendeeBridgeHelpers::CALLBACK.sub("https://", "https://user@"),
      "https://deccanqueenonrails.com/native/attendee/%2e%2e/callback", "https://deccanqueenonrails.com/native/attendee/*", "custom://callback", nil ]
    invalid.each do |callback|
      ENV["NATIVE_ATTENDEE_CLIENT_CALLBACKS"] = { "dqor-ios" => callback }.to_json
      expect(NativeAttendee::Clients.mapping).to be_empty
    end
    ENV["NATIVE_ATTENDEE_CLIENT_CALLBACKS"] = { "dqor-ios" => NativeAttendeeBridgeHelpers::CALLBACK, "dqor-android" => NativeAttendeeBridgeHelpers::CALLBACK }.to_json
    expect(NativeAttendee::Clients.mapping).to be_empty
    ENV["NATIVE_ATTENDEE_CLIENT_CALLBACKS"] = '{"dqor-ios":"' + NativeAttendeeBridgeHelpers::CALLBACK + '","dqor-ios":"' + NativeAttendeeBridgeHelpers::CALLBACK + '"}'
    expect(NativeAttendee::Clients.mapping).to be_empty
  end
end
