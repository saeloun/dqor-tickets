require "rails_helper"

RSpec.describe BroadcastAnnouncementJob, type: :job do
  include ActiveJob::TestHelper

  it "emails the announcement to each distinct paid attendee and records emailed_at" do
    order = create(:order, :paid)
    create(:ticket, order:, attendee_email: "a@example.com")
    create(:ticket, order:, attendee_email: "b@example.com")
    announcement = Announcement.create!(title: "Know before you go", body: "Doors open at 8:30am.")

    expect {
      described_class.perform_now(announcement)
    }.to have_enqueued_mail(AnnouncementMailer, :to_attendee).twice

    expect(announcement.reload.emailed_at).to be_present
  end

  it "does not re-send an announcement that was already emailed" do
    announcement = Announcement.create!(title: "X", body: "y", emailed_at: Time.current)

    expect {
      described_class.perform_now(announcement)
    }.not_to have_enqueued_mail(AnnouncementMailer, :to_attendee)
  end

  it "renders a branded email to the attendee" do
    announcement = Announcement.new(title: "Hi there", body: "Line one.\n\nLine two.")

    mail = AnnouncementMailer.to_attendee(announcement, "x@example.com")

    expect(mail.to).to eq([ "x@example.com" ])
    expect(mail.subject).to eq("Hi there")
    expect(mail.body.encoded).to include("Line one").and include("Line two")
  end
end
