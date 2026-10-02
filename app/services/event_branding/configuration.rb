module EventBranding
  # Server-side branding contract. Asset IDs must additionally be scoped to the
  # singleton setting by the persistence layer; accepting an ID grants no access.
  class Configuration
    class Invalid < StandardError; end

    VERSION = 1
    THEMES = %w[conference marathon campus].freeze
    FONTS = {
      "editorial" => 'Georgia, "Times New Roman", serif',
      "modern" => "Arial, Helvetica, sans-serif",
      "humanist" => "Trebuchet MS, Arial, sans-serif"
    }.freeze
    SECTIONS = %w[about programme visit].freeze
    ASSETS = %w[logo cover favicon].freeze
    KEYS = %w[version theme accent surface font sections assets].freeze
    PRESETS = {
      "conference" => { "accent" => "#803c35", "surface" => "#f5f0e7", "font" => "editorial" }.freeze,
      "marathon" => { "accent" => "#d8f250", "surface" => "#142c27", "font" => "modern" }.freeze,
      "campus" => { "accent" => "#754424", "surface" => "#f7eecf", "font" => "editorial" }.freeze
    }.freeze

    def self.defaults(theme = "conference")
      raise Invalid, "Choose an available theme" unless THEMES.include?(theme)

      new({ "version" => VERSION, "theme" => theme, "sections" => SECTIONS.dup, "assets" => {} }.merge(PRESETS.fetch(theme)))
    end

    def initialize(input)
      raise Invalid, "Branding must be a configuration object" unless input.is_a?(Hash)
      raise Invalid, "Unsupported branding fields" unless input.keys.sort == KEYS.sort
      raise Invalid, "Unsupported branding version" unless input["version"] == VERSION
      raise Invalid, "Choose an available theme" unless THEMES.include?(input["theme"])
      raise Invalid, "Choose an available heading font" unless FONTS.key?(input["font"])

      %w[accent surface].each do |key|
        raise Invalid, "Use a six-digit hexadecimal color" unless input[key].is_a?(String) && /\A#[0-9a-fA-F]{6}\z/.match?(input[key])
      end
      sections = input["sections"]
      unless sections.is_a?(Array) && sections.length == SECTIONS.length && sections.all? { |section| SECTIONS.include?(section) } && sections.uniq.length == SECTIONS.length
        raise Invalid, "Include each supported section exactly once"
      end
      assets = input["assets"]
      unless assets.is_a?(Hash) && (assets.keys - ASSETS).empty? && assets.values.all? { |id| id.is_a?(Integer) && id.positive? && id <= 9_223_372_036_854_775_807 }
        raise Invalid, "Assets must reference managed branding images"
      end

      # Own every nested object; callers cannot mutate a previously validated snapshot.
      @configuration = copy(input)
    end

    def to_h
      copy(@configuration)
    end

    def asset_ids
      @configuration.fetch("assets").values.uniq
    end

    def tokens
      {
        "--dq-accent" => @configuration.fetch("accent"),
        "--dq-accent-ink" => foreground(@configuration.fetch("accent")),
        "--dq-surface" => @configuration.fetch("surface"),
        "--dq-ink" => foreground(@configuration.fetch("surface")),
        "--dq-display-font" => FONTS.fetch(@configuration.fetch("font"))
      }
    end

    private
      def copy(value)
        case value
        when Hash then value.transform_values { |item| copy(item) }
        when Array then value.map { |item| copy(item) }
        when String then value.dup
        else value
        end
      end

      def foreground(color)
        channels = color.delete_prefix("#").scan(/../).map do |channel|
          value = channel.to_i(16) / 255.0
          value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
        end
        luminance = channels.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |value, weight| value * weight }
        luminance > 0.179 ? "#000000" : "#ffffff"
      end
  end
end
