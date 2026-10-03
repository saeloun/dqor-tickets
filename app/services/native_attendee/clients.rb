module NativeAttendee
  module Clients
    IDS = %w[dqor-ios dqor-android].freeze
    HOST = "deccanqueenonrails.com"

    def self.enabled?
      ENV["NATIVE_ATTENDEE_SESSION_API_ENABLED"] == "true"
    end

    def self.mapping
      values = JSON.parse(ENV.fetch("NATIVE_ATTENDEE_CLIENT_CALLBACKS", ""), allow_duplicate_key: false)
      return {} unless values.is_a?(Hash) && values.any? && (values.keys - IDS).empty?
      return {} unless values.values.all? { |value| valid_callback?(value) }
      return {} unless values.values.uniq.size == values.size

      values
    rescue JSON::ParserError, URI::InvalidURIError
      {}
    end

    def self.valid_callback?(value)
      return false unless value.is_a?(String) && value.bytesize <= 512

      uri = URI.parse(value)
      uri.is_a?(URI::HTTPS) && uri.host == HOST && uri.port == 443 && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
        uri.path.start_with?("/native/attendee/") && !uri.path.include?("%") && !uri.path.include?("*") && !uri.path.include?("..")
    end

    def self.allowed?(client_id, callback_uri)
      client_id.is_a?(String) && callback_uri.is_a?(String) && mapping[client_id] == callback_uri
    end

    def self.name(client_id)
      { "dqor-ios" => "DQOR for iOS", "dqor-android" => "DQOR for Android" }.fetch(client_id)
    end
  end
end
