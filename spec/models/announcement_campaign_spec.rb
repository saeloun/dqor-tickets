require "rails_helper"

RSpec.describe AnnouncementCampaign do
  let(:admin) { create(:admin_user) }
  let(:announcement) { Announcement.create!(title: "Hello", body: "Approved content") }
  let!(:preference) { AnnouncementPreference.create!(email: "one@example.com", consented_at: Time.current) }
  let!(:ticket) { create(:ticket, order: create(:order, :paid), attendee_email: preference.email) }

  def approve(digest = described_class.review_digest(announcement, described_class.audience))
    described_class.approve!(announcement: announcement, admin: admin, review_digest: digest)
  end

  it "normalizes legacy addresses and deduplicates across orders" do
    create(:ticket, order: create(:order, :paid), attendee_email: preference.email).update_columns(attendee_email: " ONE@example.com ")
    create(:ticket, order: create(:order, :paid), attendee_email: "no-consent@example.com")
    expect(described_class.audience).to eq([ preference.email ])
    expect(approve.audience_count).to eq(1)
  end

  it "rejects changed content and changed audience after preview" do
    digest = described_class.review_digest(announcement, described_class.audience)
    announcement.update!(body: "Changed")
    expect { approve(digest) }.to raise_error(described_class::ApprovalError, /changed/)
    digest = described_class.review_digest(announcement, described_class.audience)
    preference.update!(suppressed_at: Time.current)
    expect { approve(digest) }.to raise_error(described_class::ApprovalError, /changed/)
  end

  it "rejects desk staff, previously emailed announcements, and double approval" do
    admin.update!(role: :desk)
    expect { approve }.to raise_error(described_class::ApprovalError, /Administrator/)
    admin.update!(role: :admin)
    approve
    expect { approve }.to raise_error(described_class::ApprovalError, /already/)
    expect(AnnouncementDelivery.count).to eq(1)
  end

  it "rejects audiences above the bounded campaign size" do
    stub_const("AnnouncementCampaign::MAX_RECIPIENTS", 0)
    expect { approve }.to raise_error(described_class::ApprovalError, /audience/)
    expect(AnnouncementDelivery.count).to eq(0)
  end

  it "bounds the outstanding ledger without applying any receipt quota" do
    stub_const("AnnouncementCampaign::MAX_OUTSTANDING", 0)
    expect { approve }.to raise_error(described_class::ApprovalError, /backlog/)
    expect(AnnouncementDelivery.count).to eq(0)
  end

  it "enforces uniqueness at the database boundary" do
    campaign = approve
    expect {
      AnnouncementDelivery.transaction(requires_new: true) do
        campaign.announcement_deliveries.create!(email: preference.email)
      end
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
