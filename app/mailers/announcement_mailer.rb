class AnnouncementMailer < ApplicationMailer
  def to_attendee(announcement, email)
    @announcement = announcement
    preference = AnnouncementPreference.find_by(email: email)
    @unsubscribe_token = preference&.signed_id(purpose: :announcement_unsubscribe)
    mail(to: email, subject: announcement.title)
  end
end
