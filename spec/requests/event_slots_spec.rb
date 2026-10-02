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
    own = create(:ticket, attendee_email: user.email, order: create(:order, :paid))
    other = create(:ticket, attendee_email: "other@example.test", order: create(:order, :paid, email: user.email))
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
    get account_redemptions_path, params: { ticket_id: other.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("##{own.id}")
    expect(response.body).not_to include("##{other.id}", own.secret, other.secret)
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
    expect(response.body).not_to include("##{ticket.id}")
  end

  it "requires attendee authentication" do
    get account_redemptions_path
    expect(response).to redirect_to(account_sign_in_path)
  end
end
