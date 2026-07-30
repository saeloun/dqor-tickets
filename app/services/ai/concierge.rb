module Ai
  class Concierge
    ENDPOINT = "https://api.anthropic.com/v1/messages".freeze
    MODEL = "claude-haiku-4-5-20251001".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the friendly concierge for Deccan Queen on Rails, a Ruby and Rails conference in Pune, India.
      Facts you know for certain:
      - Dates: October 8 to 11, 2026. Talks are on October 8 and 9; October 11 is an optional Explore Pune Day.
      - Venue: Hyatt Regency, Pune.
      - Tickets: conference passes plus an optional Explore Pune Day add-on, priced in INR with GST included. People buy them on the tickets page.
      - Attendees can sign in by email (no password required), view their tickets and entry QR, and connect with other attendees in the community directory.
      Answer attendee questions concisely and warmly in under 120 words. If you are unsure of a specific detail, say so and point them to deccanqueenonrails.com. Never invent schedule details, speakers, or prices.
    PROMPT

    class << self
      def available?
        api_key.present?
      end

      def answer(question)
        question = question.to_s.strip
        return fallback if question.blank? || !available?

        response = request(question)
        return fallback unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body).dig("content", 0, "text").presence || fallback
      rescue StandardError => error
        Rails.logger.error("Ai::Concierge error: #{error.class}: #{error.message}")
        fallback
      end

      def fallback
        "Our concierge isn’t available right now. For dates, venue, and tickets, see deccanqueenonrails.com or the tickets page."
      end

      private
        def api_key
          ENV["ANTHROPIC_API_KEY"]
        end

        def request(question)
          uri = URI(ENDPOINT)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 5
          http.read_timeout = 20

          post = Net::HTTP::Post.new(uri)
          post["x-api-key"] = api_key
          post["anthropic-version"] = "2023-06-01"
          post["content-type"] = "application/json"
          post.body = JSON.generate(
            model: MODEL,
            max_tokens: 400,
            system: SYSTEM_PROMPT,
            messages: [ { role: "user", content: question } ]
          )

          http.request(post)
        end
    end
  end
end
