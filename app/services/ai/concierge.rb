module Ai
  class Concierge
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the friendly concierge for Deccan Queen on Rails, a Ruby and Rails conference in Pune, India.
      Facts you know for certain:
      - Dates: October 8 to 11, 2026. Talks are on October 8 and 9; October 11 is an optional Explore Pune Day.
      - Venue: Hyatt Regency, Pune.
      - Tickets: conference passes plus an optional Explore Pune Day add-on, priced in INR with GST included. People buy them on the tickets page.
      - Attendees can sign in by email (no password required), view their tickets and entry QR, and connect with other attendees in the community directory.
      Answer attendee questions concisely and warmly in under 120 words. If you are unsure of a specific detail, say so and point them to deccanqueenonrails.com. Never invent schedule details, speakers, or prices.
    PROMPT

    # First provider whose env key is present wins. "chat" providers use the
    # OpenAI-compatible chat/completions shape; "messages" uses the Anthropic shape.
    PROVIDERS = [
      { key: "OPENAI_API_KEY", endpoint: "https://api.openai.com/v1/chat/completions", model_env: "CONCIERGE_MODEL", model: "gpt-4o-mini", format: :chat },
      { key: "ANTHROPIC_API_KEY", endpoint: "https://api.anthropic.com/v1/messages", model_env: "CONCIERGE_MODEL", model: "claude-haiku-4-5-20251001", format: :messages },
      { key: "KIMI_API_KEY", endpoint: "https://api.moonshot.ai/v1/chat/completions", model_env: "CONCIERGE_MODEL", model: "kimi-k2-0711-preview", format: :chat },
      { key: "MOONSHOT_API_KEY", endpoint: "https://api.moonshot.cn/v1/chat/completions", model_env: "CONCIERGE_MODEL", model: "moonshot-v1-8k", format: :chat }
    ].freeze

    class << self
      def provider
        PROVIDERS.find { |candidate| ENV[candidate[:key]].present? }
      end

      def available?
        provider.present?
      end

      def answer(question)
        question = question.to_s.strip
        return fallback if question.blank?

        config = provider
        return fallback unless config

        response = request(config, question)
        return fallback unless response.is_a?(Net::HTTPSuccess)

        parse(config[:format], response.body).presence || fallback
      rescue StandardError => error
        Rails.logger.error("Ai::Concierge error: #{error.class}: #{error.message}")
        fallback
      end

      def fallback
        "Our concierge isn’t available right now. For dates, venue, and tickets, see deccanqueenonrails.com or the tickets page."
      end

      private
        def request(config, question)
          uri = URI(config[:endpoint])
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 5
          http.read_timeout = 20

          post = Net::HTTP::Post.new(uri)
          post["content-type"] = "application/json"
          post.body = body_for(config, question)
          headers_for(config).each { |name, value| post[name] = value }

          http.request(post)
        end

        def model_for(config)
          ENV[config[:model_env]].presence || config[:model]
        end

        def headers_for(config)
          if config[:format] == :messages
            { "x-api-key" => ENV[config[:key]], "anthropic-version" => "2023-06-01" }
          else
            { "authorization" => "Bearer #{ENV[config[:key]]}" }
          end
        end

        def body_for(config, question)
          if config[:format] == :messages
            JSON.generate(model: model_for(config), max_tokens: 400, system: SYSTEM_PROMPT, messages: [ { role: "user", content: question } ])
          else
            JSON.generate(model: model_for(config), max_tokens: 400, messages: [ { role: "system", content: SYSTEM_PROMPT }, { role: "user", content: question } ])
          end
        end

        def parse(format, response_body)
          data = JSON.parse(response_body)
          if format == :messages
            data.dig("content", 0, "text")
          else
            data.dig("choices", 0, "message", "content")
          end
        end
    end
  end
end
