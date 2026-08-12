class PushAnnouncementJob < ApplicationJob
  queue_as :default

  def perform(announcement)
    return unless WebPushNotifier.configured?

    body = ActionController::Base.helpers.strip_tags(announcement.body.to_s).squish.truncate(140)
    path = Rails.application.routes.url_helpers.updates_path

    User.where(id: PushSubscription.select(:user_id).distinct).find_each do |user|
      WebPushNotifier.deliver(user, title: announcement.title, body: body, path: path, tag: "announcement-#{announcement.id}")
    end
  end
end
