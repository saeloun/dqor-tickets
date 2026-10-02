# Deliberately does not inherit ApplicationJob's provider/network retry handlers.
class BroadcastAnnouncementJob < ActiveJob::Base
  queue_as :announcements
  limits_concurrency to: 1, key: "announcement-dispatch", duration: 10.minutes

  def self.enabled?
    Rails.env.test? ? ActionMailer::Base.delivery_method == :test : ENV["ANNOUNCEMENT_DELIVERY_ENABLED"] == "true"
  end

  # Legacy jobs carrying an Announcement cannot authorize a campaign or send it.
  # Approval persists the ledger; the recurring dispatcher drains bounded batches.
  def perform(*legacy_arguments)
    return if legacy_arguments.any? || !self.class.enabled?
    AnnouncementDelivery.recover_stale!
    AnnouncementDispatchLimit::PER_MINUTE.times do
      delivery = AnnouncementDispatchLimit.claim
      break unless delivery
      submit(delivery)
    end
  end

  private
    def submit(delivery)
      unless AnnouncementPreference.eligible?(delivery.email)
        AnnouncementDelivery.where(id: delivery.id, state: "preparing", attempts: delivery.attempts).update_all(state: "suppressed")
        return
      end
      campaign = delivery.announcement_campaign
      mail = AnnouncementMailer.to_attendee(campaign, delivery.email).message
      mail.encoded # Render before crossing the transport boundary.
      unless AnnouncementPreference.eligible?(delivery.email)
        AnnouncementDelivery.where(id: delivery.id, state: "preparing", attempts: delivery.attempts).update_all(state: "suppressed")
        return
      end
      # This committed marker must precede the non-transactional provider call.
      claimed = AnnouncementDelivery.where(id: delivery.id, state: "preparing", attempts: delivery.attempts)
      return unless claimed.update_all(state: "submitting") == 1
      begin
        mail.deliver!
        delivery.update!(state: "submitted", submitted_at: Time.current)
      rescue StandardError => error
        delivery.update!(state: "unknown", error_class: error.class.name)
      end
    rescue StandardError => error
      # Failure after submission is never automatically made retryable.
      failed = AnnouncementDelivery.where(id: delivery.id, state: "preparing", attempts: delivery.attempts)
        .update_all(state: "failed", error_class: error.class.name)
      raise if failed.zero?
    end
end
