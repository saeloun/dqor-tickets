class WebPushNotifier
  def self.deliver(title:, body:, path: "/", to: PushSubscription.all)
    message = JSON.generate(
      title: title,
      options: { body: body, icon: "/icon.png", data: { path: path } }
    )

    to.find_each do |subscription|
      WebPush.payload_send(
        message: message,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh_key,
        auth: subscription.auth_key,
        vapid: { subject: Vapid::SUBJECT, public_key: Vapid.public_key, private_key: Vapid.private_key }
      )
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      subscription.destroy
    end
  end
end
