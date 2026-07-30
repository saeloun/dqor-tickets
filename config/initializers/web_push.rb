module Vapid
  SUBJECT = "mailto:hello@deccanqueenonrails.com"

  class << self
    def public_key
      keys[:public_key]
    end

    def private_key
      keys[:private_key]
    end

    def configured?
      configured_keys.present?
    end

    def keys
      @keys ||= configured_keys || generated_keys
    end

    private
      def configured_keys
        credentials = Rails.application.credentials.vapid
        if credentials && credentials[:public_key].present? && credentials[:private_key].present?
          return { public_key: credentials[:public_key], private_key: credentials[:private_key] }
        end

        if ENV["VAPID_PUBLIC_KEY"].present? && ENV["VAPID_PRIVATE_KEY"].present?
          return { public_key: ENV["VAPID_PUBLIC_KEY"], private_key: ENV["VAPID_PRIVATE_KEY"] }
        end

        nil
      end

      def generated_keys
        key = WebPush.generate_key
        { public_key: key.public_key, private_key: key.private_key }
      end
  end
end
