require "rails_helper"

RSpec.describe "Free pilot authentication privacy", type: :request do
  let(:email) { "pilot-google@example.test" }
  let(:state) { "x" * 32 }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "pilot-google", info: { email: email, name: "Pilot Google" },
      extra: { raw_info: { email_verified: true } }
    )
  end

  after do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def pilot_origin
    get free_organizations_path
    expect(response).to redirect_to(account_sign_in_path)
  end

  def verify(user)
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  it "keeps the public event sign-in navigation inside the private pilot flow" do
    org = Organization.create!(name: "Community", slug: "auth-community")
    event = org.events.create!(title: "Meetup", slug: "meetup", status: :published, starts_at: Time.current, ends_at: 1.day.from_now)
    get published_event_path(org.slug, event.slug)
    link = Nokogiri::HTML(response.body).css("nav a").find { |item| item.text == "Sign in" }
    expect(link["href"]).to eq(free_tickets_path)
    get link["href"]
    post account_sign_in_path, params: { email: email }
    expect(User.find_by!(email: email)).to have_attributes(free_pilot_identity: true, discoverable: false)
  end

  it "rejects fresh pilot Google callbacks without creating a discoverable identity and retains canceled/retried context" do
    pilot_origin
    get "/auth/failure"
    2.times do
      expect { get "/auth/google_oauth2/callback" }.not_to change(User, :count)
      expect(response).to redirect_to(account_sign_in_path)
    end
    post account_sign_in_path, params: { email: email }
    user = User.find_by!(email: email)
    expect(user).to have_attributes(free_pilot_identity: true, discoverable: false, public_attendee: false)
    verify(user)
    expect(response).to redirect_to(free_organizations_path)
    expect(User.legacy_network).not_to include(user)
  end

  it "keeps existing non-DQOR Google users private after email verification, including a disabled-pilot retry" do
    user = create(:user_for_free_pilot, email: email, discoverable: true, public_attendee: true)
    pilot_origin
    get "/auth/google_oauth2/callback"
    expect(response).to redirect_to(account_sign_in_path)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(false)
    get "/auth/google_oauth2/callback"
    verify(user)
    expect(user.reload).to have_attributes(free_pilot_identity: true, discoverable: false, public_attendee: false)
    expect(User.legacy_network).not_to include(user)
  end

  it "preserves an existing shared DQOR user's explicit choices" do
    user = create(:user_for_free_pilot, email: email, discoverable: true, public_attendee: true)
    create(:order, email: email, status: :paid)
    pilot_origin
    get "/auth/google_oauth2/callback"
    verify(user)
    expect(user.reload).to have_attributes(free_pilot_identity: false, discoverable: true, public_attendee: true)
  end

  it "rejects the freshly authenticated pilot-only chat identity despite a different eligible session and disabled flags" do
    pilot = create(:user_for_free_pilot, email: email)
    FreeEvents::Privacy.enroll!(pilot)
    verify(create(:user_for_free_pilot))
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(false)
    get chat_login_path, params: { state: state }
    expect { get "/auth/google_oauth2/callback" }.not_to change(ChatLoginGrant, :count)
    expect(response).to redirect_to(account_sign_in_path)
    expect { ChatLoginGrant.issue!(email: email, name: "Pilot", state: state) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "rejects and consumes a chat grant when its identity enrolls privately after issuance" do
    user = create(:user_for_free_pilot, email: email)
    code = ChatLoginGrant.issue!(email: email, name: "Pilot", state: state)
    FreeEvents::Privacy.enroll!(user)
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(false)
    post redeem_chat_login_path, params: { login_code: code, state: state }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(ChatLoginGrant.count).to eq(0)
  end
end
