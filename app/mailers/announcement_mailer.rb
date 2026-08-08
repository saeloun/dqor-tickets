class AnnouncementMailer < ApplicationMailer
  def to_attendee(announcement, email)
    @announcement = announcement
    mail(to: email, subject: announcement.title)
  end
end
