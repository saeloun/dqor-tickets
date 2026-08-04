class AnnouncementMailerPreview < ActionMailer::Preview
  def to_attendee
    announcement = Announcement.recent.first || Announcement.new(
      title: "Know before you go — Deccan Queen on Rails",
      body: "Doors open at 8:30am at the venue in Pune. Bring your QR entry pass — it's in your account and your ticket email.\n\nDay 1 kicks off at 9:30am with the keynote. Chai and breakfast are served from 8:30.\n\nSee you there!"
    )
    AnnouncementMailer.to_attendee(announcement, "attendee@example.com")
  end
end
