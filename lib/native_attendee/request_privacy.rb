require "delegate"

module NativeAttendee
  class RequestPrivacy
    PATHS = [ "/account/native", "/api/native/attendee", "/native/attendee" ].freeze
    PARAMETERS = [ :code_verifier, :code_challenge, :redirect_uri, :authorization, :cookie ].freeze

    class ParseLogger < SimpleDelegator
      def debug(message = nil, &block)
        if message.is_a?(String) && message.start_with?("Error occurred while parsing request parameters.")
          __getobj__.debug("Error occurred while parsing native request parameters. [FILTERED]")
        else
          __getobj__.debug(message, &block)
        end
      end
    end

    def initialize(app)
      @app = app
    end

    def self.normalized_path(path)
      ActionDispatch::Journey::Router::Utils.normalize_path(path.to_s)
    end

    def self.private_path?(path)
      path = normalized_path(path)
      PATHS.any? { |prefix| path == prefix || path.start_with?(prefix + "/") }
    end

    def self.referrer_policy(path)
      path = normalized_path(path)
      path == "/account/native" || path.start_with?("/account/native/") ? "strict-origin" : "no-referrer"
    end

    def self.filter_event(event)
      url = event.request&.url
      private_path?(URI.parse(url.to_s).path) ? nil : event
    rescue URI::InvalidURIError
      event
    end

    def self.install_filters(configuration)
      previous_error_filter = configuration.before_send
      previous_transaction_filter = configuration.before_send_transaction
      configuration.before_send = ->(event, hint) { filter_event(event) && (previous_error_filter ? previous_error_filter.call(event, hint) : event) }
      configuration.before_send_transaction = ->(event, hint) { filter_event(event) && (previous_transaction_filter ? previous_transaction_filter.call(event, hint) : event) }
    end

    def self.with_private_scope
      if defined?(Sentry) && Sentry.initialized?
        Sentry.with_scope do |scope|
          scope.clear_breadcrumbs
          scope.add_event_processor { |_event, _hint| nil }
          yield
        end
      else
        yield
      end
    end

    def call(env)
      path = self.class.normalized_path(env["PATH_INFO"])
      return @app.call(env) unless self.class.private_path?(path)

      unless NativeAttendee::Clients.enabled?
        policy = self.class.referrer_policy(path)
        return [ 404, { "content-type" => "application/json; charset=utf-8", "cache-control" => "private, no-store", "referrer-policy" => policy,
          "content-security-policy" => "default-src 'none'; frame-ancestors 'none'" }, [ '{"schema_version":1,"error":{"code":"not_found"}}' ] ]
      end

      env["action_dispatch.logger"] = ParseLogger.new(env["action_dispatch.logger"] || Rails.logger)
      env["action_dispatch.parameter_filter"] = Array(env["action_dispatch.parameter_filter"]) + PARAMETERS
      env["action_dispatch.redirect_filter"] = [ /.*/ ]
      if path == "/native/attendee" || path.start_with?("/native/attendee/")
        return [ 410, { "content-type" => "text/plain; charset=utf-8", "cache-control" => "private, no-store", "referrer-policy" => "no-referrer", "content-security-policy" => "default-src 'none'" }, [ "Return to the app and start a new sign-in request." ] ]
      end
      result = self.class.with_private_scope { @app.call(env) }
      status, headers, body = result
      headers = headers.dup
      headers["cache-control"] = "private, no-store"
      headers["referrer-policy"] = self.class.referrer_policy(path)
      headers.delete("etag")
      headers.delete("last-modified")
      [ status, headers, body ]
    end
  end
end
