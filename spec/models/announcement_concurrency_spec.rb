require "rails_helper"

RSpec.describe "Announcement concurrency", type: :model do
  self.use_transactional_tests = false

  def race
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          yield
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.map(&:value)
  ensure
    threads&.each { |thread| thread.join(5) }
  end

  it "serializes double approval and concurrent recipient claims across database connections" do
    admin = create(:admin_user)
    announcement = Announcement.create!(title: "Concurrency", body: "Once only")
    preference = AnnouncementPreference.create!(email: "concurrent@example.com", consented_at: Time.current)
    order = create(:order, :paid)
    type = create(:ticket_type)
    ticket = create(:ticket, order: order, ticket_type: type, attendee_email: preference.email)
    digest = AnnouncementCampaign.review_digest(announcement, AnnouncementCampaign.audience)
    results = race do
      AnnouncementCampaign.approve!(announcement: Announcement.find(announcement.id), admin: admin, review_digest: digest)
      :approved
    rescue AnnouncementCampaign::ApprovalError
      :rejected
    end
    expect(results).to match_array([ :approved, :rejected ])
    campaign = AnnouncementCampaign.find_by!(announcement: announcement)
    expect(campaign.announcement_deliveries.count).to eq(1)
    AnnouncementDispatchLimit.control.update!(used: 0, window_started_at: Time.current)
    results = race { AnnouncementDispatchLimit.claim&.id }
    expect(results.compact).to eq([ campaign.announcement_deliveries.sole.id ])
    expect(AnnouncementDispatchLimit.find(1).used).to eq(1)
  ensure
    if announcement
      campaigns = AnnouncementCampaign.where(announcement: announcement)
      AnnouncementDelivery.where(announcement_campaign_id: campaigns.select(:id)).delete_all
      campaigns.delete_all
      announcement.destroy!
    end
    preference&.destroy!
    ticket&.destroy!
    order&.destroy!
    type&.destroy!
    admin&.destroy!
    AnnouncementDispatchLimit.where(id: 1).delete_all
  end
end
