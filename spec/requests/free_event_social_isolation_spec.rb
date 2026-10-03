require "rails_helper"

RSpec.describe "Free pilot social isolation", type: :request do
  let!(:pilot) { create(:user_for_free_pilot, name: "PRIVATE PILOT", discoverable: true, public_attendee: true) }
  let!(:legacy) { create(:user_for_free_pilot, name: "Legacy Person", discoverable: true) }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
  end

  def login(user)
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  it "creates pilot-origin accounts private before they verify or participate" do
    get free_organizations_path
    expect(response).to redirect_to(account_sign_in_path)
    post account_sign_in_path, params: { email: "new-pilot@example.test" }
    fresh = User.find_by!(email: "new-pilot@example.test")
    expect(fresh).to have_attributes(free_pilot_identity: true, discoverable: false, public_attendee: false)
    expect(User.legacy_network).not_to include(fresh)
    login(legacy)
    get attendee_path(fresh)
    expect(response).to have_http_status(:not_found)
  end

  it "excludes pilot-only identity from legacy search, direct profiles and connection creation even after opt-in flags are forged" do
    login(pilot)
    get free_organizations_path
    expect(pilot.reload).to have_attributes(free_pilot_identity: true, discoverable: false, public_attendee: false)
    patch account_settings_path, params: { user: { discoverable: true, public_attendee: true } }
    login(legacy)
    get community_path
    expect(response.body).not_to include("PRIVATE PILOT")
    get attendee_path(pilot)
    expect(response).to have_http_status(:not_found)
    expect { post connect_attendee_path(pilot) }.not_to change(Connection, :count)
    expect(response).to have_http_status(:not_found)
    expect { post account_conversations_path, params: { attendee_id: pilot.id } }.not_to change(Conversation, :count)
    expect(legacy.can_message?(pilot)).to be(false)
    expect { legacy.connections.create!(connected_user: pilot) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "blocks pilot actors from legacy networking and push with the pilot flag subsequently off" do
    FreeEvents::Privacy.enroll!(pilot)
    login(pilot)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(false)
    [ community_path, attendee_path(legacy), account_conversations_path, account_connection_scan_path ].each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
    end
    post connect_attendee_path(legacy)
    expect(response).to have_http_status(:not_found)
    post account_push_subscriptions_path, params: { subscription: { endpoint: "https://example.test/push", keys: { p256dh: "a", auth: "b" } } }
    expect(response).to have_http_status(:not_found)
    expect(PushSubscription.where(user: pilot)).to be_empty
  end

  it "denies pre-existing one-way DM history, new messages, and queued pushes after pilot enrollment" do
    legacy.connections.create!(connected_user: pilot)
    conversation = Conversation.between(legacy, pilot)
    message = conversation.messages.create!(sender: legacy, body: "old private chat")
    subscription = pilot.push_subscriptions.create!(endpoint: "https://example.test/push", p256dh: "a", auth: "b")
    FreeEvents::Privacy.enroll!(pilot)
    login(legacy)
    get account_conversation_path(conversation)
    expect(response.body).not_to include("old private chat")
    expect { post account_conversation_messages_path(conversation), params: { message: { body: "unsolicited" } } }.not_to change(Message, :count)
    expect { conversation.messages.create!(sender: legacy, body: "bypass") }.to raise_error(ActiveRecord::RecordInvalid)
    allow(WebPushNotifier).to receive(:configured?).and_return(true)
    expect(WebPushNotifier).not_to receive(:deliver)
    PushMessageJob.perform_now(message)
    expect(WebPush).not_to receive(:payload_send)
    expect(WebPushNotifier.deliver_one(subscription, title: "No", body: "No")).to be(false)
  end

  it "retains legacy visibility choices for shared DQOR attendees and still hides private direct profiles" do
    create(:ticket, order: create(:order, :paid, email: pilot.email), attendee_email: pilot.email)
    FreeEvents::Privacy.enroll!(pilot)
    expect(pilot.reload).to have_attributes(free_pilot_identity: false, discoverable: true, public_attendee: true)
    login(legacy)
    get attendee_path(pilot)
    expect(response).to have_http_status(:ok)
    pilot.update!(discoverable: false)
    get attendee_path(pilot)
    expect(response).to have_http_status(:not_found)
    expect { post connect_attendee_path(pilot) }.not_to change(Connection, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "does not create a social directory or connection across two free events" do
    2.times do |index|
      org = Organization.create!(name: "Free #{index}", slug: "free-#{index}")
      event = org.events.create!(title: "Free", slug: "free", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now)
      type = create(:ticket_type, event_id: event.id, price_paise: 0, hidden: true, active: false, capacity: 2, free_published_at: Time.current)
      FreeEvents::Register.call(user: index.zero? ? pilot : legacy, event_id: event.id, ticket_type_id: type.id)
    end
    expect(User.legacy_network.where(id: [ pilot.id, legacy.id ])).to be_empty
    expect(pilot.can_message?(legacy)).to be(false)
    login(pilot)
    get attendee_path(legacy)
    expect(response).to have_http_status(:not_found)
  end
end
