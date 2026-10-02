class AnnouncementCampaign < ApplicationRecord
  MAX_RECIPIENTS = 5_000
  MAX_OUTSTANDING = 10_000
  class ApprovalError < StandardError; end

  belongs_to :announcement
  belongs_to :admin_user
  has_many :announcement_deliveries, dependent: :restrict_with_exception
  validates :title, :content_digest, :approved_at, presence: true

  def readonly?
    persisted?
  end

  def self.audience
    Ticket.broadcast_recipients
  end

  def self.review_digest(announcement, emails)
    Digest::SHA256.hexdigest([ announcement.title, announcement.body.to_s, emails.sort ].to_json)
  end

  def self.approve!(announcement:, admin:, review_digest:)
    raise ApprovalError, "Administrator access required" unless admin&.admin?
    announcement.with_lock do
      raise ApprovalError, "This announcement is already approved or was previously emailed." if announcement.emailed_at? || exists?(announcement: announcement)
      emails = audience
      raise ApprovalError, "Audience or content changed. Review the preview again." unless review_digest == self.review_digest(announcement, emails)
      raise ApprovalError, "Choose an audience between 1 and #{MAX_RECIPIENTS} opted-in attendees." unless emails.size.between?(1, MAX_RECIPIENTS)
      AnnouncementDispatchLimit.control
      AnnouncementDispatchLimit.lock.find(1)
      outstanding = AnnouncementDelivery.where(state: %w[pending preparing submitting]).count
      raise ApprovalError, "Announcement backlog is full. Wait for existing deliveries before approving more." if outstanding + emails.size > MAX_OUTSTANDING
      campaign = create!(announcement: announcement, admin_user: admin, title: announcement.title,
        body: announcement.body.to_s, content_digest: Digest::SHA256.hexdigest([ announcement.title, announcement.body.to_s ].to_json),
        approved_at: Time.current, audience_count: emails.size)
      campaign.announcement_deliveries.insert_all!(emails.map { |email| { email: email, created_at: Time.current, updated_at: Time.current } })
      campaign
    end
  end
end
