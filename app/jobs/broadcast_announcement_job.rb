class BroadcastAnnouncementJob < ApplicationJob
  queue_as :default

  # Emails an announcement to every attendee holding a paid, non-canceled ticket.
  # Idempotent: guarded by emailed_at so a re-run never double-sends.
  def perform(announcement)
    return if announcement.emailed_at?

    Ticket.broadcast_recipients.each do |email|
      AnnouncementMailer.to_attendee(announcement, email).deliver_later
    end

    PushAnnouncementJob.perform_later(announcement)

    announcement.update!(emailed_at: Time.current)
  end
end
