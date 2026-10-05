module FreeEvents::Questions
  module Schema
    TYPES = { "short_text" => "Short text", "long_text" => "Long text", "integer" => "Whole number", "single_choice" => "Choose one", "yes_no" => "Yes or no" }.freeze
    UNSUPPORTED_CONTROL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/
    ID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    def self.enabled?
      FreeEvents::Access.enabled? && Rails.configuration.x.free_event_questions_enabled
    end

    def self.require_enabled!
      raise ActiveRecord::RecordNotFound unless enabled?
    end

    def self.validate!(questions)
      errors = {}
      raise Invalid, { "form" => "Use up to 12 questions" } unless questions.is_a?(Array) && questions.length <= 12
      Array(questions).each do |q|
        unless q.is_a?(Hash) && q.keys.sort == %w[help id label options required type] && q["id"].to_s.match?(ID)
          errors["form"] = "Invalid question definition"
          next
        end
        errors[q["id"]] = "Each question needs a label (up to 160 characters), valid type and required setting" unless
          q["label"].is_a?(String) && q["label"].strip.present? && q["label"].length <= 160 && TYPES.key?(q["type"]) && [ true, false ].include?(q["required"])
        errors[q["id"]] = "Helper text must be at most 300 characters" unless q["help"].is_a?(String) && q["help"].length <= 300
        options = q["options"]
        if q["type"] == "single_choice"
          valid = options.is_a?(Array) && (2..10).cover?(options.length) && options.all? { |o| o.is_a?(Hash) && o.keys.sort == %w[id label] && o["id"].to_s.match?(ID) && o["label"].is_a?(String) && o["label"].strip.present? && o["label"].length <= 100 }
          valid &&= options.map { |o| o["id"] }.uniq.length == options.length && options.map { |o| o["label"] }.uniq.length == options.length
          errors[q["id"]] = "Add 2–10 distinct choices, each up to 100 characters" unless valid
        elsif options != []
          errors[q["id"]] = "Only choice questions can have options"
        end
      end
      errors["form"] = "Question identifiers must be unique" unless questions.filter_map { |q| q["id"] if q.is_a?(Hash) }.uniq.length == Array(questions).length
      errors["form"] = "Remove unsupported control characters" if questions.any? { |q| q.is_a?(Hash) && [ q["label"], q["help"], *Array(q["options"]).filter_map { |o| o["label"] if o.is_a?(Hash) } ].any? { |text| text.to_s.match?(UNSUPPORTED_CONTROL) } }
      raise Invalid, errors if errors.any?
      questions
    end

    def self.answers!(version, raw)
      raise Invalid, { "form" => "Answers must be a field map" } unless raw.is_a?(Hash)
      questions = version.questions
      errors = {}
      errors["form"] = "Unknown questions were submitted; reload the form" if (raw.keys - questions.map { |q| q["id"] }).any?
      answers = questions.to_h do |q|
        value = raw[q["id"]]
        if !value.nil? && !value.is_a?(String)
          errors[q["id"]] = "Enter a single value"
          next [ q["id"], nil ]
        end
        if value.to_s.match?(UNSUPPORTED_CONTROL)
          errors[q["id"]] = "Remove unsupported control characters"
          next [ q["id"], nil ]
        end
        value = value.to_s.strip
        if value.empty?
          errors[q["id"]] = "This answer is required" if q["required"]
          next [ q["id"], nil ]
        end
        case q["type"]
        when "short_text", "long_text"
          limit = q["type"] == "short_text" ? 200 : 1000
          errors[q["id"]] = "Use at most #{limit} characters" if value.length > limit
        when "integer"
          if value.match?(/\A-?\d{1,7}\z/) && (-1_000_000..1_000_000).cover?(value.to_i)
            value = value.to_i
          else
            errors[q["id"]] = "Enter a whole number between -1000000 and 1000000"
          end
        when "yes_no"
          errors[q["id"]] = "Choose yes or no" unless %w[yes no].include?(value)
          value = value == "yes"
        when "single_choice"
          errors[q["id"]] = "Choose one of the listed options" unless q["options"].any? { |option| option["id"] == value }
        end
        [ q["id"], value ]
      end
      raise Invalid, errors if errors.any?
      answers
    end
  end
end
