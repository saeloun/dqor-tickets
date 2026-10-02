require "rails_helper"

RSpec.describe "Announcement campaign authorization", type: :request do
  let!(:announcement) { Announcement.create!(title: "News", body: '<script>alert("x")</script>') }

  it "requires organizer authentication for preview, approval, draft and retry" do
    get announcement_campaign_path(announcement)
    expect(response).to redirect_to(new_session_path)
    sign_in_admin(create(:admin_user, role: :desk, password: "password123"))
    get announcement_campaign_path(announcement)
    expect(response).to have_http_status(:forbidden)
    get draft_announcement_campaign_path(announcement)
    expect(response).to have_http_status(:forbidden)
    post announcement_campaign_path(announcement)
    expect(response).to have_http_status(:forbidden)
    post retry_failed_announcement_campaign_path(announcement)
    expect(response).to have_http_status(:forbidden)
  end

  it "previews safely and downloads an admin-addressed draft without delivering" do
    admin = sign_in_admin
    get announcement_campaign_path(announcement)
    expect(response.body).to include("0 recipients")
    expect(response.body).not_to include('<script>alert("x")</script>')
    expect {
      get draft_announcement_campaign_path(announcement)
    }.not_to change { ActionMailer::Base.deliveries.size }
    expect(response.media_type).to eq("message/rfc822")
    expect(Mail.read_from_string(response.body).to).to eq([ admin.email ])
    expect(Mail.read_from_string(response.body).subject).to include("NOT SENT")
  end

  it "only retries failed preparation up to three attempts" do
    admin = sign_in_admin
    campaign = AnnouncementCampaign.create!(announcement: announcement, admin_user: admin, title: "News", body: "Body", content_digest: "test", audience_count: 3, approved_at: Time.current)
    failed = campaign.announcement_deliveries.create!(email: "a@example.com", state: "failed", attempts: 1)
    exhausted = campaign.announcement_deliveries.create!(email: "b@example.com", state: "failed", attempts: 3)
    unknown = campaign.announcement_deliveries.create!(email: "c@example.com", state: "unknown", attempts: 1)
    post retry_failed_announcement_campaign_path(announcement)
    expect(failed.reload.state).to eq("pending")
    expect(exhausted.reload.state).to eq("failed")
    expect(unknown.reload.state).to eq("unknown")
  end

  it "only lets authenticated attendees change their own consent" do
    patch account_announcement_preference_path, params: { subscribe: "1" }
    expect(response).to redirect_to(account_sign_in_path)
    user = User.create!(email: "self@example.com")
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
    patch account_announcement_preference_path, params: { subscribe: "1", email: "other@example.com" }
    expect(AnnouncementPreference.consented.pluck(:email)).to eq([ user.email ])
    expect(AnnouncementPreference.find_by!(email: user.email).consent_source).to eq("authenticated_account_settings")
    patch account_announcement_preference_path, params: { subscribe: "0" }
    expect(AnnouncementPreference.consented).to be_empty
  end

  it "requires a valid signed unsubscribe token and does not unsubscribe on GET" do
    preference = AnnouncementPreference.create!(email: "a@example.com", consented_at: Time.current)
    token = preference.signed_id(purpose: :announcement_unsubscribe)
    get announcement_unsubscribe_path(token: token)
    expect(preference.reload.suppressed_at).to be_nil
    post announcement_unsubscribe_path(token: token)
    expect(preference.reload.suppressed_at).to be_present
    post announcement_unsubscribe_path(token: "tampered")
    expect(response).to have_http_status(:not_found)
  end
end
