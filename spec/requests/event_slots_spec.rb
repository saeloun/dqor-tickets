require "rails_helper"

RSpec.describe "Event slots", type: :request do
  it "limits schedule editing to existing admins" do
    sign_in_admin(create(:admin_user, role: :desk))
    get new_event_slot_path
    expect(response).to have_http_status(:forbidden)
    post event_slots_path, params: { event_slot: { name: "Forbidden" } }
    expect(response).to have_http_status(:forbidden)
  end

  it "creates draft schedules with explicit empty eligibility and IST times" do
    sign_in_admin
    post event_slots_path, params: { event_slot: { name: "Synthetic Day1 party", starts_at: "2026-10-08T18:00", ends_at: "2026-10-08T20:00", redemption_limit: 1, ticket_type_ids: [ "" ] } }
    expect(response).to redirect_to(event_slots_path)
    expect(EventSlot.last).not_to be_active
    expect(EventSlot.last.ticket_type_ids).to eq([])
    expect(EventSlot.last.starts_at.utc.hour).to eq(12)
  end

  it "shows only the authenticated attendee's records and never QR secrets" do
    user = User.create!(email: "own@example.test", password: "password123")
    # Ticket #14 must not be confused with the layout's #141110 theme color.
    own = create(:ticket, id: 13, attendee_email: user.email, order: create(:order, :paid))
    other = create(:ticket, id: 14, attendee_email: "other@example.test", order: create(:order, :paid, email: user.email))
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
    get account_redemptions_path, params: { ticket_id: other.id }
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("main article h2").map(&:text)).to eq([ "#{own.ticket_type.name} · ##{own.id}" ])
    expect(response.body).not_to include(own.secret, other.secret)
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "does not treat requesting a sign-in email as verified identity" do
    user = User.create!(email: "unverified@example.test")
    create(:ticket, attendee_email: user.email)
    post account_sign_in_path, params: { email: user.email }
    get account_redemptions_path
    expect(response).to redirect_to(account_sign_in_path)
  end

  it "binds verification to the current email and clears it on logout or account switch" do
    user = User.create!(email: "Verified@Example.test")
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
    get account_redemptions_path
    expect(response).to have_http_status(:ok)
    user.update!(email: "changed@example.test")
    get account_redemptions_path, params: { verified_attendee_email: user.email }
    expect(response).to redirect_to(account_sign_in_path)
    delete account_sign_out_path
    get account_redemptions_path, params: { verified_attendee_email: "verified@example.test" }
    expect(response).to redirect_to(account_sign_in_path)
    other = User.create!(email: "switch@example.test")
    token = Rails.application.message_verifier(:account_magic_link).generate(other.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
    ticket = create(:ticket, attendee_email: user.email, order: create(:order, :paid))
    get account_redemptions_path
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("main article")).to be_empty
  end

  it "requires attendee authentication" do
    get account_redemptions_path
    expect(response).to redirect_to(account_sign_in_path)
  end
end

RSpec.describe "Slot manual fallback", type: :request do
  it "requires staff authentication for lookup and redemption" do
    slot = EventSlot.create!(name: "Draft", starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    get event_slot_path(slot), params: { q: "someone" }
    expect(response).to redirect_to(new_session_path)
    post redeem_event_slot_path(slot), params: { ticket_id: 1, request_key: SecureRandom.uuid }
    expect(response).to redirect_to(new_session_path)
  end

  it "returns bounded secret-free lookup and enforces identical eligibility for manual redemption" do
    sign_in_admin(create(:admin_user, role: :desk))
    ticket = create(:ticket, attendee_name: "Synthetic Manual", order: create(:order, :paid))
    slot = EventSlot.create!(name: "Draft lunch", starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    get event_slot_path(slot), params: { q: "Synthetic Manual" }
    expect(response.body).to include(ticket.attendee_name)
    expect(response.body).not_to include(ticket.secret, ticket.claim_token)
    post redeem_event_slot_path(slot), params: { ticket_id: ticket.id, request_key: SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(EventSlotRedemption.count).to eq(0)
  end
end
