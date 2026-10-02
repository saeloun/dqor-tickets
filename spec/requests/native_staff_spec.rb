require "rails_helper"

RSpec.describe "Native staff API", type: :request do
  let(:operator) { create(:admin_user, role: :desk, password: "password123") }
  let(:date) { "2026-10-08" }
  let(:ticket) { create(:ticket, order: create(:order, :paid)) }

  before do
    allow(NativeStaffSession).to receive(:enabled?).and_return(true)
    allow(NativeStaffSession).to receive(:configured_dates).and_return([ date ])
  end

  def login
    post "/api/staff/session", params: { email: operator.email, password: "password123" }, as: :json
    expect(response).to have_http_status(:created)
    @token = response.parsed_body.fetch("access_token")
  end

  def headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def resolve(day: date)
    post "/api/staff/checkins/resolve", params: { secret: ticket.secret, date: day }, headers:, as: :json
  end

  def confirm(ids = [ ticket.id ], confirmed: true, day: date)
    post "/api/staff/checkins/confirm", params: { ticket_ids: ids, date: day, confirmed: }, headers:, as: :json
  end

  it "is disabled by default and fails closed without configured event dates" do
    allow(NativeStaffSession).to receive(:enabled?).and_return(false)
    post "/api/staff/session", params: {}, as: :json
    expect(response).to have_http_status(:not_found)
    allow(NativeStaffSession).to receive(:enabled?).and_return(true)
    allow(NativeStaffSession).to receive(:configured_dates).and_return([])
    post "/api/staff/session", params: {}, as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(NativeStaffSession.count).to eq(0)
  end

  it "authenticates existing staff, stores only a token digest, and returns bounded capabilities" do
    login
    expect(response.parsed_body).to include("event" => "dqor-2026", "event_dates" => [ date ], "capabilities" => %w[tickets:read checkins:write])
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(NativeStaffSession.last.token_digest).to eq(Digest::SHA256.hexdigest(@token))
    expect(NativeStaffSession.last.attributes.values).not_to include(@token)
    expect(NativeStaffSession.last.expires_at).to be_within(2.seconds).of(8.hours.from_now)
    expect(response.cookies).not_to have_key("session_id")
    get "/api/staff/session", headers:, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(@token)
  end

  it "rate limits credential attempts" do
    store = ActiveSupport::Cache::MemoryStore.new
    allow(Api::Staff::SessionsController.cache_store).to receive(:increment) do |*args, **options|
      store.increment(*args, **options)
    end
    11.times { post "/api/staff/session", params: { email: operator.email, password: "incorrect" }, as: :json }
    expect(response).to have_http_status(:too_many_requests)
    expect(NativeStaffSession.count).to eq(0)
  end

  it "rejects wrong credentials and attendee accounts" do
    User.create!(email: "attendee@example.test")
    post "/api/staff/session", params: { email: "attendee@example.test", password: "password123" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "/api/staff/session", params: { email: operator.email, password: "incorrect" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(NativeStaffSession.count).to eq(0)
  end

  it "rejects missing or malformed tokens and does not accept web staff cookies" do
    sign_in_admin(operator)
    resolve
    expect(response).to have_http_status(:unauthorized)
    @token = "invalid"
    resolve
    expect(response).to have_http_status(:unauthorized)
    expect(ticket.reload.checked_in_at).to be_empty
  end

  it "resolves a QR without attendance or audit mutation and never returns its secret" do
    login
    resolve
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("state" => "resolved", "date" => date)
    expect(response.parsed_body.fetch("ticket")).to include("id" => ticket.id, "eligible" => true, "checked_in_at" => nil)
    expect(response.body).not_to include(ticket.secret, ticket.claim_token)
    expect(ticket.reload.checked_in_at).to be_empty
    expect(CheckinAudit.count).to eq(0)
  end

  it "enforces event-day and capability scope on reads and writes" do
    login
    resolve(day: "2026-10-09")
    expect(response).to have_http_status(:forbidden)
    confirm(day: "2026-10-09")
    expect(response).to have_http_status(:forbidden)
    NativeStaffSession.last.update!(capabilities: [ "tickets:read" ])
    confirm
    expect(response).to have_http_status(:forbidden)
    resolve
    expect(response).to have_http_status(:ok)
    NativeStaffSession.last.update!(capabilities: [])
    resolve
    expect(response).to have_http_status(:forbidden)
    expect(ticket.reload.checked_in_at).to be_empty
  end

  it "requires explicit confirmation and bounds selected IDs" do
    login
    confirm(confirmed: false)
    expect(response).to have_http_status(:unprocessable_content)
    confirm((1..51).to_a)
    expect(response).to have_http_status(:unprocessable_content)
    confirm([ "all" ])
    expect(response).to have_http_status(:unprocessable_content)
    expect(ticket.reload.checked_in_at).to be_empty
  end

  it "rechecks eligibility after preview and records explicit per-ticket outcomes" do
    login
    resolve
    ticket.update!(canceled_at: Time.current)
    good = create(:ticket, order: create(:order, :paid))
    confirm([ ticket.id, good.id ])
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("results").pluck("state")).to eq(%w[error success])
    expect(ticket.reload.checked_in_at).to be_empty
    expect(good.reload.checked_in_at).to have_key(date)
  end

  it "makes confirmation retries idempotent for attendance" do
    login
    confirm([ ticket.id, ticket.id ])
    original = ticket.reload.checked_in_at
    expect(response.parsed_body.fetch("results").size).to eq(1)
    confirm
    expect(response.parsed_body.fetch("results").first.fetch("state")).to eq("warning")
    expect(ticket.reload.checked_in_at).to eq(original)
    expect(CheckinAudit.where(outcome: "success", admin_user: operator).count).to eq(1)
  end

  it "denies replay after logout, expiry, password change, or role change" do
    login
    delete "/api/staff/session", headers:, as: :json
    expect(response).to have_http_status(:no_content)
    resolve
    expect(response).to have_http_status(:unauthorized)
    login
    NativeStaffSession.last.update!(expires_at: 1.second.ago)
    resolve
    expect(response).to have_http_status(:unauthorized)
    login
    operator.update!(role: :admin)
    resolve
    expect(response).to have_http_status(:unauthorized)
    login
    operator.update!(password: "replacement-password")
    resolve
    expect(response).to have_http_status(:unauthorized)
  end

  it "denies a revoked database session and reduced runtime event scope" do
    login
    allow(NativeStaffSession).to receive(:configured_dates).and_return([ "2026-10-09" ])
    resolve
    expect(response).to have_http_status(:forbidden)
    NativeStaffSession.last.destroy!
    resolve
    expect(response).to have_http_status(:unauthorized)
  end

  it "does not authenticate bearer tokens against the web dashboard" do
    login
    get "/avo/resources/tickets", headers: headers
    expect(response).to redirect_to("/session/new")
  end

  it "bounds lookup and returns no QR secrets" do
    login
    create_list(:ticket, 21, order: create(:order, :paid))
    get "/api/staff/checkins", params: { date: }, headers:, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("tickets").size).to eq(20)
    expect(response.parsed_body.fetch("more_results")).to be(true)
    expect(response.body).not_to include('"secret"', '"claim_token"')
  end

  it "rolls back the native confirmation transaction if an audit fails" do
    login
    first = ticket
    second = create(:ticket, order: create(:order, :paid))
    allow(CheckinAudit).to receive(:create!).and_call_original
    allow(CheckinAudit).to receive(:create!).with(hash_including(ticket: second)).and_raise(ActiveRecord::RecordInvalid)
    confirm([ first.id, second.id ])
    expect(response).to have_http_status(:unprocessable_content)
    expect(first.reload.checked_in_at).to be_empty
    expect(second.reload.checked_in_at).to be_empty
    expect(CheckinAudit.count).to eq(0)
  end
end
