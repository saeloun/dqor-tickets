require "rails_helper"

RSpec.describe "Attendee read API", type: :request do
  let(:user) { User.create!(email: "verified@example.test", name: "Verified Attendee") }
  let(:account_path) { "/api/attendee/v1/account" }
  let(:passes_path) { "/api/attendee/v1/passes" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("NATIVE_ATTENDEE_READ_API_ENABLED").and_return("true")
  end

  around(:each, :google_callback) do |example|
    previous_mode = OmniAuth.config.test_mode
    previous_auth = OmniAuth.config.mock_auth[:google_oauth2]
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.mock_auth[:google_oauth2] = previous_auth
    OmniAuth.config.test_mode = previous_mode
  end

  def sign_in_attendee(identity = user, expires_in: 30.minutes)
    token = Rails.application.message_verifier(:account_magic_link).generate(identity.id, purpose: :account_magic_link, expires_in: expires_in)
    get account_magic_path(token: token)
  end

  def expect_private_json(status)
    expect(response).to have_http_status(status)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
    expect(response.headers["ETag"]).to be_nil
    expect(response.headers["Last-Modified"]).to be_nil
    expect(response.headers["Location"]).to be_nil
  end

  def assigned_pass(**attributes)
    create(:ticket, order: create(:order, :paid), attendee_name: user.name, attendee_email: user.email, **attributes)
  end

  def passes
    response.parsed_body.fetch("passes")
  end

  it "reads the account through the existing magic link and rejects the current browser after logout" do
    perform_enqueued_jobs(only: MailDeliveryJob) do
      post account_sign_in_path, params: { email: user.email }
    end
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ user.email ])
    link = URI.parse(mail.text_part.body.decoded.lines.find { |line| line.start_with?("http") }.strip)
    get link.request_uri
    expect(response).to redirect_to(account_root_path)
    get account_path
    expect_private_json(:ok)
    expect(response.parsed_body).to include("schema_version" => 1, "event" => "dqor-2026", "account" => { "id" => user.id.to_s, "name" => user.name, "email" => user.email })
    expect(Time.iso8601(response.parsed_body.fetch("checked_at"))).to be_within(2.seconds).of(Time.current)
    delete account_sign_out_path
    [ account_path, passes_path ].each do |path|
      get path
      expect_private_json(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
      expect(response.body).not_to include(user.email)
    end
  end

  it "returns only stored admission bounds and existing per-day entry state without pass secrets" do
    type = create(:ticket_type, name: "RailsGirls", event_starts_on: Date.new(2026, 10, 10), event_ends_on: Date.new(2026, 10, 10))
    ticket = assigned_pass(ticket_type: type, checked_in_at: { "2026-10-10" => "2026-10-10T09:00:00+05:30" })
    sign_in_attendee
    get passes_path
    expect_private_json(:ok)
    expect(passes).to eq([ {
      "id" => ticket.id.to_s, "type" => { "id" => type.id.to_s, "name" => "RailsGirls" }, "status" => "confirmed",
      "admission" => { "starts_on" => "2026-10-10", "ends_on" => "2026-10-10" },
      "entry" => Ticket::EVENT_DATES.map { |date| { "date" => date.iso8601, "eligible" => date.day == 10, "checked_in_at" => date.day == 10 ? "2026-10-10T09:00:00+05:30" : nil } }
    } ])
    expect(response.body).not_to include(ticket.secret, ticket.claim_token, ticket.order.code, ticket.order.email, "buyer_phone", "price", "food", "party", "refund", "url")
  end

  it "is disabled unless the opt-in is exactly true and keeps errors private" do
    [ nil, "false", "TRUE", "1" ].each do |setting|
      allow(ENV).to receive(:[]).with("NATIVE_ATTENDEE_READ_API_ENABLED").and_return(setting)
      [ account_path, passes_path ].each do |path|
        get path
        expect_private_json(:not_found)
        expect(response.parsed_body.dig("error", "code")).to eq("not_found")
      end
    end
  end

  it "rejects production HTTP with JSON and accepts HTTPS for a verified attendee" do
    sign_in_attendee
    allow(Rails.env).to receive(:production?).and_return(true)
    [ account_path, passes_path ].each do |path|
      get path
      expect_private_json(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("https_required")
    end
    https!
    get account_path
    expect_private_json(:ok)
  end

  it "rejects every supplied Authorization header even alongside a verified session" do
    sign_in_attendee
    [ "Bearer #{SecureRandom.urlsafe_base64(32)}", "Basic abc", "", "unexpected" ].each do |value|
      [ account_path, passes_path ].each do |path|
        get path, headers: { "Authorization" => value }
        expect_private_json(:forbidden)
        expect(response.parsed_body.dig("error", "code")).to eq("authorization_not_supported")
        expect(response.body).not_to include(user.email, value.presence || "__absent__")
      end
    end
  end

  it "does not treat a staff login cookie or a valid staff bearer as attendee identity" do
    operator = sign_in_admin(create(:admin_user, role: :desk))
    [ account_path, passes_path ].each do |path|
      get path
      expect_private_json(:unauthorized)
    end
    allow(NativeStaffSession).to receive(:enabled?).and_return(true)
    allow(NativeStaffSession).to receive(:configured_dates).and_return([ "2026-10-08" ])
    post "/api/staff/session", params: { email: operator.email, password: "password123" }, as: :json
    token = response.parsed_body.fetch("access_token")
    get account_path, headers: { "Authorization" => "Bearer #{token}" }
    expect_private_json(:forbidden)
    expect(response.body).not_to include(token, operator.email)
  end

  it "rejects expired and tampered magic links without creating a verified session" do
    sign_in_attendee(expires_in: -1.second)
    get account_path
    expect_private_json(:unauthorized)
    get account_magic_path(token: "tampered")
    get passes_path
    expect_private_json(:unauthorized)
  end

  it "requires matching email-link proof even when Google verifies the current user", :google_callback do
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "synthetic", info: { email: user.email, name: user.name }, extra: { raw_info: { email_verified: true } })
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    get "/auth/google_oauth2/callback"
    expect(response).to redirect_to(account_root_path)
    [ account_path, passes_path ].each do |path|
      get path
      expect_private_json(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("email_verification_required")
      expect(response.body).not_to include(user.email)
    end
    sign_in_attendee
    user.update!(email: "changed@example.test")
    get passes_path
    expect_private_json(:forbidden)
  end

  it "excludes buyer-only ownership, another attendee, and unassigned passes" do
    mine = assigned_pass
    purchased = create(:order, :paid, email: user.email)
    create(:ticket, order: purchased, attendee_email: "other@example.test", attendee_name: "Other")
    create(:ticket, order: purchased, attendee_email: nil, attendee_name: nil)
    create(:ticket, attendee_email: user.email, attendee_name: nil)
    sign_in_attendee
    get passes_path
    expect_private_json(:ok)
    expect(passes.pluck("id")).to eq([ mine.id.to_s ])
    other = User.create!(email: "someoneelse@example.test")
    sign_in_attendee(other)
    get passes_path
    expect_private_json(:ok)
    expect(passes).to be_empty
  end

  it "matches normalized stored assignment and rechecks reassignments live" do
    ticket = assigned_pass
    ticket.update_columns(attendee_email: "  VERIFIED@EXAMPLE.TEST  ")
    sign_in_attendee
    get passes_path
    expect(passes.pluck("id")).to eq([ ticket.id.to_s ])
    ticket.update!(attendee_email: "reassigned@example.test")
    get passes_path
    expect(passes).to be_empty
  end

  it "rechecks cancellation, payment, and pending expiry without changing commerce state" do
    ticket = assigned_pass
    sign_in_attendee
    ticket.order.update!(expires_at: 1.hour.ago)
    get passes_path
    expect(passes.first.fetch("status")).to eq("confirmed")
    ticket.order.update!(status: :pending, expires_at: 1.hour.from_now)
    get passes_path
    expect(passes.first.fetch("status")).to eq("pending")
    expect(passes.first.fetch("entry").pluck("eligible")).to eq([ false ] * 4)
    ticket.order.update!(expires_at: 1.second.ago)
    get passes_path
    expect(passes.first.fetch("status")).to eq("expired")
    expect(ticket.order.reload).to be_pending
    ticket.order.update!(status: :paid)
    get passes_path
    expect(passes.first.fetch("status")).to eq("confirmed")
    ticket.update!(canceled_at: Time.current)
    get passes_path
    expect(passes.first.fetch("status")).to eq("canceled")
    expect(passes.first.fetch("entry").pluck("eligible")).to eq([ false ] * 4)
    ticket.update!(canceled_at: nil)
    ticket.order.update!(status: :canceled)
    get passes_path
    expect(passes.first.fetch("status")).to eq("canceled")
    ticket.order.update!(status: :expired)
    get passes_path
    expect(passes.first.fetch("status")).to eq("expired")
  end

  it "uses exact stored ranges, one-sided dates and null bounds" do
    [ [ "2026-10-08", "2026-10-09", [ true, true, false, false ] ],
      [ "2026-10-10", nil, [ false, false, true, true ] ],
      [ nil, "2026-10-09", [ true, true, false, false ] ],
      [ nil, nil, [ true, true, true, true ] ] ].each do |start_date, end_date, eligible|
      assigned_pass(ticket_type: create(:ticket_type, event_starts_on: start_date, event_ends_on: end_date))
    end
    sign_in_attendee
    get passes_path
    expect(passes.map { |pass| pass.fetch("admission") }).to eq([
      { "starts_on" => "2026-10-08", "ends_on" => "2026-10-09" },
      { "starts_on" => "2026-10-10", "ends_on" => nil },
      { "starts_on" => nil, "ends_on" => "2026-10-09" },
      { "starts_on" => nil, "ends_on" => nil }
    ])
    expect(passes.map { |pass| pass.fetch("entry").pluck("eligible") }).to eq([
      [ true, true, false, false ], [ false, false, true, true ], [ true, true, false, false ], [ true, true, true, true ]
    ])
  end

  it "excludes free tenants and rejects every mismatched ticket/order/type ownership combination" do
    mine = assigned_pass
    tenants = Array.new(2) do |index|
      organization = Organization.create!(name: "Private tenant #{index}", slug: "private-#{index}")
      event = organization.events.create!(title: "Private event", slug: "private-event")
      type = create(:ticket_type, event_id: event.id, name: "Private type #{index}", price_paise: 0, hidden: true, active: false)
      order = create(:order, :paid, event_id: event.id, user_id: user.id, total_paise: 0)
      create(:ticket, event_id: event.id, order: order, ticket_type: type, price_paise: 0, attendee_name: user.name, attendee_email: user.email)
      { event_id: event.id, order: order, ticket_type: type }
    end
    choices = [ { event_id: nil, order: mine.order, ticket_type: mine.ticket_type }, *tenants ]
    choices.repeated_permutation(3) do |ticket_owner, order_owner, type_owner|
      next if [ ticket_owner, order_owner, type_owner ].uniq.size == 1

      expect {
        Ticket.transaction(requires_new: true) do
          create(:ticket, event_id: ticket_owner[:event_id], order: order_owner[:order], ticket_type: type_owner[:ticket_type], price_paise: 0, attendee_name: user.name, attendee_email: user.email)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
    sign_in_attendee
    get passes_path
    expect_private_json(:ok)
    expect(passes.pluck("id")).to eq([ mine.id.to_s ])
    expect(response.body).not_to include("Private type", "Private tenant", tenants.first[:order].code)
  end

  it "rejects a deleted account instead of trusting the existing cookie" do
    sign_in_attendee
    user.destroy!
    get account_path
    expect_private_json(:unauthorized)
  end

  it "paginates at most 20 assigned IDs with no cursor derived from other attendees" do
    assigned = Array.new(22) { assigned_pass }
    foreign = create(:ticket)
    sign_in_attendee
    get passes_path, params: { limit: 9999 }
    expect_private_json(:ok)
    expect(passes.pluck("id")).to eq(assigned.first(20).map { |ticket| ticket.id.to_s })
    expect(response.parsed_body.fetch("more_results")).to be(true)
    expect(response.parsed_body.fetch("next_cursor")).to eq(assigned[19].id.to_s)
    get passes_path, params: { cursor: response.parsed_body.fetch("next_cursor") }
    expect_private_json(:ok)
    expect(passes.pluck("id")).to eq(assigned.last(2).map { |ticket| ticket.id.to_s })
    expect(response.parsed_body.fetch("more_results")).to be(false)
    expect(response.parsed_body.fetch("next_cursor")).to be_nil
    get passes_path, params: { cursor: foreign.id.to_s }
    expect(passes).to be_empty
    expect(response.parsed_body.fetch("next_cursor")).to be_nil
    get passes_path, params: { cursor: "9223372036854775807" }
    expect_private_json(:ok)
    expect(passes).to be_empty
  end

  it "rejects noncanonical, structured or out-of-range cursors without revealing passes" do
    assigned_pass
    sign_in_attendee
    [ "", "0", "01", "-1", "+1", "1.0", " 1", "1e1", "9223372036854775808", "9" * 100, [ "1" ], { value: "1" } ].each do |cursor|
      get passes_path, params: { cursor: cursor }
      expect_private_json(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_cursor")
      expect(response.body).not_to include(user.email, "passes")
    end
  end

  it "never serves cached PII or requires an HTML browser on either JSON endpoint" do
    assigned_pass
    sign_in_attendee
    travel_to Time.current.change(usec: 0) do
      [ account_path, passes_path ].each do |path|
        get path
        snapshot = response.body
        would_be_etag = %(W/"#{Digest::SHA256.hexdigest(snapshot).byteslice(0, 32)}")
        get path, headers: { "If-None-Match" => would_be_etag, "If-Modified-Since" => 1.day.from_now.httpdate, "User-Agent" => "Mozilla/5.0 Chrome/60.0.0.0" }
        expect_private_json(:ok)
        expect(response.body).to eq(snapshot)
      end
    end
  end

  it "performs no database writes, audit, mail, message or job work while reading" do
    assigned_pass
    sign_in_attendee
    clear_enqueued_jobs
    writes = []
    observer = ->(_name, _start, _finish, _id, payload) { writes << payload[:sql] if payload[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) }
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") do
      get account_path, params: { ref: "SHOULDNOTPERSIST" }
      expect_private_json(:ok)
      get passes_path
      expect_private_json(:ok)
    end
    expect(writes).to be_empty
    expect(enqueued_jobs).to be_empty
    expect(CheckinAudit.count).to eq(0)
    expect(EventSlotRedemption.count).to eq(0)
    expect(Message.count).to eq(0)
    expect(request.session[:ref]).to be_nil
  end

  it "only declares GET routes and no individual or mutation endpoint" do
    routes = Rails.application.routes.routes.select { |route| route.path.spec.to_s.start_with?("/api/attendee/") }
    expect(routes.map(&:verb)).to eq([ "GET", "GET" ])
    expect(routes.map { |route| route.path.spec.to_s }).to contain_exactly("/api/attendee/v1/account(.:format)", "/api/attendee/v1/passes(.:format)")
  end
end
