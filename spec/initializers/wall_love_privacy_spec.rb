require "rails_helper"
require "sentry/rails/controller_transaction"

RSpec.describe "Wall of Love Sentry privacy" do
  let(:configuration) { Sentry::Configuration.new }
  let(:client) { Sentry::Client.new(configuration) }
  let(:hub) { Sentry::Hub.new(client, Sentry::Scope.new) }
  let(:attributes) { { public_name: "SYNTHETIC_PUBLIC_NAME_913", note: "SYNTHETIC_NOTE_913", source_url: "https://example.test/SYNTHETIC_SOURCE_913" } }
  let(:markers) { %w[SYNTHETIC_PUBLIC_NAME_913 SYNTHETIC_NOTE_913 SYNTHETIC_SOURCE_913] }

  before do
    allow(Sentry).to receive(:init).and_yield(configuration)
    old_dsn = ENV["SENTRY_DSN"]
    original_filters = Rails.application.config.filter_parameters.dup
    ENV["SENTRY_DSN"] = "https://synthetic@telemetry.example.test/1"
    begin
      load Rails.root.join("config/initializers/sentry.rb")
    ensure
      ENV["SENTRY_DSN"] = old_dsn
      Rails.application.config.filter_parameters = original_filters
    end
    configuration.transport.transport_class = Sentry::DummyTransport
    configuration.background_worker_threads = 0
    configuration.environment = "test"
    configuration.enabled_environments = [ "test" ]
    allow(Sentry).to receive(:initialized?).and_return(true)
    allow(Sentry).to receive(:get_current_hub).and_return(hub)
  end

  def error_event
    Sentry::ErrorEvent.new(configuration: configuration, message: "Synthetic request error")
  end

  def transaction_event
    transaction = Sentry::Transaction.new(name: "WallOfLoveController#create", op: "http.server", sampled: true)
    Sentry::TransactionEvent.new(configuration: configuration, transaction: transaction)
  end

  def attach_request(event, path)
    env = Rack::MockRequest.env_for("https://example.test#{path}", method: "POST")
    event.rack_env = env
    event
  end

  def dispatch(event)
    expect(client.send_event(event)).to equal(event)
    expect(client.transport).to be_a(Sentry::DummyTransport)
    expect(client.transport.events.last).to equal(event)
    client.transport.events.last.to_h
  end

  it "shares the sanitizer between error and transaction callbacks without changing PII settings" do
    expect(configuration.before_send_transaction).to equal(configuration.before_send)
    expect(configuration.send_default_pii).to be(false)
    expect(configuration.traces_sample_rate).to eq(0.2)
  end

  [ "error", "transaction" ].each do |kind|
    [ "structured", "raw" ].each do |body_kind|
      it "scrubs #{body_kind} Wall of Love content through actual #{kind} event dispatch" do
        event = kind == "error" ? error_event : transaction_event
        attach_request(event, "/wall-of-love/review/1")
        body = { wall_love_note: attributes }
        event.request.data = body_kind == "structured" ? body : JSON.generate(body)
        event.request.query_string = Rack::Utils.build_nested_query(body)
        event.request.url = "https://example.test/wall-of-love/review/1?#{event.request.query_string}#note"

        payload = dispatch(event)

        expect(payload.dig(:request, :data)).to be_nil
        expect(payload.dig(:request, :query_string)).to be_nil
        expect(payload.dig(:request, :url)).to eq("https://example.test/wall-of-love/review/1")
        serialized = JSON.generate(payload)
        markers.each { |marker| expect(serialized).not_to include(marker) }
      end
    end

    it "preserves existing structured parameter filtering for unrelated #{kind} events" do
      event = kind == "error" ? error_event : transaction_event
      attach_request(event, "/tickets")
      event.request.data = { public_name: attributes[:public_name], note: attributes[:note], source_url: attributes[:source_url], password: "synthetic-password", count: 2 }
      event.request.query_string = "count=2"
      event.request.url = "https://example.test/tickets?count=2"

      payload = dispatch(event)

      expect(payload.dig(:request, :data)).to include(public_name: "[FILTERED]", note: "[FILTERED]", source_url: "[FILTERED]", password: "[FILTERED]", count: 2)
      expect(payload.dig(:request, :query_string)).to eq("count=2")
      expect(payload.dig(:request, :url)).to eq("https://example.test/tickets?count=2")
    end

    it "preserves unrelated raw bodies and events without requests for #{kind} dispatch" do
      event = kind == "error" ? error_event : transaction_event
      expect(dispatch(event)).not_to have_key(:request)
      attach_request(event, "/tickets")
      event.request.data = "synthetic-public-raw-body"
      expect(dispatch(event).dig(:request, :data)).to eq("synthetic-public-raw-body")
    end
  end

  [ "application/x-www-form-urlencoded", "application/json" ].each do |content_type|
    it "excludes normal #{content_type} transaction content with SDK PII disabled before the defensive callback" do
      configuration.before_send_transaction = nil
      params = { wall_love_note: attributes }
      query = Rack::Utils.build_nested_query(params)
      body = content_type == "application/json" ? JSON.generate(params) : query
      env = Rack::MockRequest.env_for("https://example.test/wall-of-love?#{query}", method: "POST", input: body, "CONTENT_TYPE" => content_type)
      env["action_dispatch.parameter_filter"] = Rails.application.config.filter_parameters
      request = ActionDispatch::Request.new(env)
      controller_class = Class.new do
        def self.prepend_around_action(*)
        end
        include Sentry::Rails::ControllerTransaction
        attr_reader :request, :response

        def initialize(request)
          @request = request
          @response = Struct.new(:status).new(200)
        end

        def action_name
          "create"
        end
      end
      stub_const("SyntheticWallLovePrivacyController", controller_class)
      scope = hub.current_scope
      scope.set_rack_env(env)
      transaction = Sentry.start_transaction(name: "WallOfLoveController#create", op: "http.server", sampled: true)
      scope.set_span(transaction)
      SyntheticWallLovePrivacyController.new(request).send(:sentry_around_action) { :complete }
      expect(configuration.before_send).not_to receive(:call)

      transaction.finish

      event = client.transport.events.last
      expect(event).to be_a(Sentry::TransactionEvent)
      payload = event.to_h
      expect(payload.dig(:request, :data)).to be_nil
      expect(payload.dig(:request, :query_string)).to be_nil
      expect(payload.dig(:request, :url)).to eq("https://example.test/wall-of-love")
      expect(payload[:spans].size).to eq(1)
      expect(payload[:spans].first[:data]).to include(params: request.filtered_parameters, path: request.filtered_path)
      expect(request.filtered_parameters["wall_love_note"]).to eq("[FILTERED]")
      serialized = JSON.generate(payload)
      markers.each { |marker| expect(serialized).not_to include(marker) }
    end
  end
end
