class AnnouncementCampaignsController < ApplicationController
  before_action :require_admin
  before_action :load_announcement

  def show
    @campaign = AnnouncementCampaign.find_by(announcement: @announcement)
    @audience = AnnouncementCampaign.audience unless @campaign
    @digest = AnnouncementCampaign.review_digest(@announcement, @audience) unless @campaign
    @counts = @campaign&.announcement_deliveries&.group(:state)&.count || {}
    @deliveries = @campaign&.announcement_deliveries&.order(:id)&.limit(100)
  end

  def create
    AnnouncementCampaign.approve!(announcement: @announcement, admin: Current.admin_user, review_digest: params[:review_digest])
    redirect_to announcement_campaign_path(@announcement), notice: "Approved content and audience saved. Delivery waits for the announcement worker."
  rescue AnnouncementCampaign::ApprovalError => error
    redirect_to announcement_campaign_path(@announcement), alert: error.message
  end

  def draft
    source = AnnouncementCampaign.find_by(announcement: @announcement) || @announcement
    mail = AnnouncementMailer.to_attendee(source, Current.admin_user.email).message
    mail.subject = "[TEST DRAFT — NOT SENT] #{source.title}"
    send_data mail.encoded, type: "message/rfc822", disposition: "attachment", filename: "announcement-test.eml"
  end

  def retry_failed
    campaign = AnnouncementCampaign.find_by!(announcement: @announcement)
    campaign.announcement_deliveries.where(state: "failed").where("attempts < 3").update_all(state: "pending", error_class: nil)
    redirect_to announcement_campaign_path(@announcement), notice: "Preparation failures queued again (maximum 3 attempts). Unknown outcomes were not retried."
  end

  private
    def require_admin
      head :forbidden unless Current.admin_user&.admin?
    end

    def load_announcement
      @announcement = Announcement.find(params[:id])
    end
end
