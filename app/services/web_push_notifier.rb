class WebPushNotifier
  class << self
    def configured?
      public_key.present? && private_key.present?
    end

    def deliver(user, title:, body:, path: "/", tag: nil)
      return 0 unless configured?

      delivered = 0
      user.push_subscriptions.find_each do |subscription|
        delivered += 1 if deliver_one(subscription, title:, body:, path:, tag:)
      end
      delivered
    end

    def deliver_one(subscription, title:, body:, path: "/", tag: nil)
      WebPush.payload_send(
        message: payload(title:, body:, path:, tag:),
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        vapid: { subject: subject, public_key: public_key, private_key: private_key }
      )
      true
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      subscription.destroy
      false
    rescue => error
      Rails.logger.warn("[web-push] #{error.class}: #{error.message}")
      Sentry.capture_exception(error) if defined?(Sentry)
      false
    end

    private
      def payload(title:, body:, path:, tag:)
        options = { body: body, data: { path: path }, icon: "/icon.png", badge: "/icon.png" }
        options[:tag] = tag if tag
        { title: title, options: options }.to_json
      end

      def public_key
        ENV["VAPID_PUBLIC_KEY"].presence
      end

      def private_key
        ENV["VAPID_PRIVATE_KEY"].presence
      end

      def subject
        ENV["VAPID_SUBJECT"].presence || "mailto:hello@deccanqueenonrails.com"
      end
  end
end
