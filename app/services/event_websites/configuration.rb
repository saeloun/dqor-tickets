module EventWebsites
  class Configuration
    class Invalid < StandardError; end

    VERSION = 1
    THEMES = EventBranding::Configuration::THEMES
    FONTS = EventBranding::Configuration::FONTS
    ASSETS = EventBranding::Configuration::ASSETS
    SECTIONS = %w[about programme sponsors venue registration].freeze
    TEXT_LIMITS = { "summary" => 300, "about" => 1200, "venue_name" => 100, "venue_address" => 300, "venue_details" => 600 }.freeze
    PROGRAMME_LIMITS = { "time" => 60, "title" => 160, "speaker" => 120 }.freeze
    SPONSOR_LIMITS = { "name" => 120, "tier" => 80 }.freeze
    KEYS = (%w[version theme accent surface font sections navigation assets programme sponsors] + TEXT_LIMITS.keys).freeze

    def self.defaults(theme = "conference")
      appearance = EventBranding::Configuration.defaults(theme).to_h
      new(appearance.merge("sections" => SECTIONS.dup, "navigation" => SECTIONS.dup, "programme" => [], "sponsors" => [], **TEXT_LIMITS.transform_values { "" }))
    rescue EventBranding::Configuration::Invalid => error
      raise Invalid, error.message
    end

    def initialize(input)
      raise Invalid, "Website must be a configuration object" unless input.is_a?(Hash)
      raise Invalid, "Unsupported website fields" unless input.keys.all? { |key| key.is_a?(String) } && input.keys.sort == KEYS.sort
      raise Invalid, "Unsupported website version" unless input["version"] == VERSION
      @appearance = EventBranding::Configuration.new(input.slice("version", "theme", "accent", "surface", "font", "assets").merge("sections" => EventBranding::Configuration::SECTIONS.dup))
      validate_targets!(input["sections"], SECTIONS, "Choose each visible section at most once")
      validate_targets!(input["navigation"], input["sections"], "Navigation must link to visible website sections")
      TEXT_LIMITS.each { |key, limit| validate_text!(input[key], limit, key.humanize) }
      validate_entries!(input["programme"], PROGRAMME_LIMITS, "title", "Programme")
      validate_entries!(input["sponsors"], SPONSOR_LIMITS, "name", "Sponsors")
      @configuration = input.deep_dup
    rescue EventBranding::Configuration::Invalid => error
      raise Invalid, error.message
    end

    def to_h
      @configuration.deep_dup
    end

    def asset_ids
      @appearance.asset_ids
    end

    def tokens
      @appearance.tokens.transform_keys { |key| key.sub("--dq-", "--ew-") }
    end

    private
      def validate_targets!(values, allowed, message)
        unless values.is_a?(Array) && values.size <= SECTIONS.size && values.all? { |value| allowed.include?(value) } && values.uniq.size == values.size
          raise Invalid, message
        end
      end

      def validate_text!(value, limit, label)
        unless value.is_a?(String) && value.valid_encoding? && value.length <= limit && !value.match?(/[<>\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
          raise Invalid, "#{label} must be plain text up to #{limit} characters"
        end
      end

      def validate_entries!(entries, limits, required, label)
        raise Invalid, "#{label} supports up to 20 entries" unless entries.is_a?(Array) && entries.size <= 20
        entries.each do |entry|
          raise Invalid, "Unsupported #{label.downcase} fields" unless entry.is_a?(Hash) && entry.keys.sort == limits.keys.sort
          limits.each { |key, limit| validate_text!(entry[key], limit, "#{label} #{key}") }
          raise Invalid, "#{label} #{required} is required" if entry.fetch(required).blank?
        end
      end
  end
end
