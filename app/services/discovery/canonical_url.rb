require "uri"
require "ipaddr"

module Discovery
  module CanonicalUrl
    class Invalid < StandardError; end

    def self.safe(value)
      call(value)
    rescue Invalid
      nil
    end

    def self.call(value)
      raise Invalid, "Use a public HTTPS URL." unless value.is_a?(String) && value.bytesize <= 2_000
      uri = URI.parse(value)
      host = uri.host.to_s.downcase
      valid_host = host.include?(".") && host.match?(/\A[a-z0-9][a-z0-9.-]*[a-z0-9]\z/) && !host.end_with?(".local", ".internal", ".test", ".localhost")
      begin
        IPAddr.new(host)
        valid_host = false
      rescue IPAddr::InvalidAddressError
      end
      raise Invalid, "Use a public HTTPS URL." unless uri.is_a?(URI::HTTPS) && valid_host && uri.userinfo.nil? && uri.port == 443
      pairs = URI.decode_www_form(uri.query.to_s)
      raise Invalid, "Private or credential-bearing URLs are not supported." if pairs.any? { |key, _| key.match?(/\A(?:token|access_token|auth|password|secret|signature|api_key|email|invite)\z/i) }
      pairs.reject! { |key, _| key.match?(/\Autm_/i) || %w[fbclid gclid].include?(key.downcase) }
      uri.host = host
      uri.fragment = nil
      uri.path = "/" if uri.path.empty?
      uri.query = pairs.empty? ? nil : URI.encode_www_form(pairs.sort)
      uri.to_s
    rescue URI::InvalidURIError, ArgumentError
      raise Invalid, "Use a valid public HTTPS URL."
    end
  end
end
