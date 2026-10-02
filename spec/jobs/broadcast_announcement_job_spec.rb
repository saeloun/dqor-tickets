require "rails_helper"

RSpec.describe BroadcastAnnouncementJob, type: :job do
  let(:admin) { create(:admin_user) }
  let(:announcement) { Announcement.create!(title: "Know before you go", body: "Doors open at 8:30am.") }
  let(:email) { "a@example.com" }
  let!(:preference) { AnnouncementPreference.create!(email: email, consented_at: Time.current) }
  let!(:ticket) { create(:ticket, order: create(:order, :paid), attendee_email: email) }

  def approve
    AnnouncementCampaign.approve!(announcement: announcement, admin: admin,
      review_digest: AnnouncementCampaign.review_digest(announcement, AnnouncementCampaign.audience))
  end

  before do
    AnnouncementDispatchLimit.control.update!(window_started_at: 2.minutes.ago, used: 0)
    ActionMailer::Base.deliveries.clear
  end

  it "reserves the existing default worker capacity from announcement traffic" do
    config = YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)
    workers = config.fetch("production").fetch("workers")
    expect(workers.first.fetch("queues")).to eq("default")
    expect(workers.first.fetch("threads")).to eq(3)
    expect(workers.last.fetch("threads")).to eq(1)
    expect(described_class.new.queue_name).to eq("announcements")
    expect(described_class.new.priority).to eq(100)
  end

  it "submits a frozen version once across repeated dispatches" do
    campaign = approve
    announcement.update!(title: "Changed", body: "Not approved")
    2.times { described_class.perform_now }
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.first.subject).to eq("Know before you go")
    expect(campaign.announcement_deliveries.sole.state).to eq("submitted")
    expect { campaign.update!(body: "tamper") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "does not treat a legacy queued job as approval" do
    described_class.perform_now(announcement)
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(AnnouncementCampaign.count).to eq(0)
  end

  it "suppresses revoked consent and canceled tickets at delivery" do
    campaign = approve
    preference.update!(suppressed_at: Time.current)
    described_class.perform_now
    expect(campaign.announcement_deliveries.sole.state).to eq("suppressed")
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "rechecks ticket eligibility" do
    campaign = approve
    ticket.update!(canceled_at: Time.current)
    described_class.perform_now
    expect(campaign.announcement_deliveries.sole.state).to eq("suppressed")
  end

  it "never resends an unknown transport outcome" do
    campaign = approve
    allow_any_instance_of(Mail::Message).to receive(:deliver!).and_raise(Net::ReadTimeout)
    2.times { described_class.perform_now }
    delivery = campaign.announcement_deliveries.sole
    expect(delivery.state).to eq("unknown")
    expect(delivery.attempts).to eq(1)
    expect(delivery.error_class).to eq("Net::ReadTimeout")
  end

  it "records a preparation failure separately from submission" do
    campaign = approve
    allow(AnnouncementMailer).to receive(:to_attendee).and_raise(ArgumentError)
    described_class.perform_now
    expect(campaign.announcement_deliveries.sole.state).to eq("failed")
  end

  it "recovers interrupted submissions as unknown" do
    delivery = approve.announcement_deliveries.sole
    delivery.update!(state: "submitting", attempted_at: 20.minutes.ago)
    described_class.perform_now
    expect(delivery.reload.state).to eq("unknown")
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "enforces the persisted global rate limit across job invocations" do
    campaign = approve
    AnnouncementDispatchLimit.control.update!(window_started_at: Time.current, used: 25)
    2.times { described_class.perform_now }
    expect(campaign.announcement_deliveries.sole.state).to eq("pending")
    travel 61.seconds do
      described_class.perform_now
      expect(campaign.announcement_deliveries.sole.state).to eq("submitted")
    end
  end

  it "fences a stale renderer after its attempt has been recovered" do
    delivery = approve.announcement_deliveries.sole
    mail = AnnouncementMailer.to_attendee(delivery.announcement_campaign, email).message
    allow(AnnouncementMailer).to receive(:to_attendee).and_return(double(message: mail))
    allow(mail).to receive(:encoded) do
      delivery.update!(state: "failed", attempted_at: 20.minutes.ago)
      "rendered"
    end
    expect(mail).not_to receive(:deliver!)
    described_class.perform_now
    expect(delivery.reload.state).to eq("failed")
  end

  it "will not use a real mail transport in the test environment" do
    approve
    allow(ActionMailer::Base).to receive(:delivery_method).and_return(:smtp)
    described_class.perform_now
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "renders escaped content and a signed unsubscribe link" do
    announcement.update!(body: '<script>alert("x")</script>')
    mail = AnnouncementMailer.to_attendee(announcement, email)
    expect(mail.html_part.body.decoded).not_to include("<script>")
    expect(mail.html_part.body.decoded).to include("announcement_unsubscribe")
  end
end
