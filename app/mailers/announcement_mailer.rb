class AnnouncementMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM", "tickets@deccanqueenonrails.com")

  def to_attendee(announcement, email)
    @announcement = announcement
    mail(to: email, subject: announcement.title)
  end
end
