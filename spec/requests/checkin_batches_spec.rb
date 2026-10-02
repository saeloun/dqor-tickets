require "rails_helper"

RSpec.describe "Staff check-in batches", type: :request do
  let(:date) { "2026-10-08" }
  let(:operator) { create(:admin_user, role: :desk) }
  let(:paid_order) { create(:order, :paid) }

  def submit(ids, confirmed: true, day: date)
    post batch_checkin_path, params: { ticket_ids: ids, date: day, confirmed: }, as: :json
  end

  it "requires a staff session for JSON reads and writes" do
    get checkin_path(format: :json)
    expect(response).to have_http_status(:unauthorized)
    submit([ 1 ])
    expect(response).to have_http_status(:unauthorized)
    expect(CheckinAudit.count).to eq(0)
  end

  it "denies an authenticated operator without an explicitly allowed role" do
    sign_in_admin(operator)
    allow_any_instance_of(AdminUser).to receive(:admin?).and_return(false)
    allow_any_instance_of(AdminUser).to receive(:desk?).and_return(false)
    get checkin_path(format: :json)
    expect(response).to have_http_status(:forbidden)
    submit([ 1 ])
    expect(response).to have_http_status(:forbidden)
    expect(CheckinAudit.count).to eq(0)
  end

  it "does not accept attendee login as staff authorization" do
    user = User.create!(email: "attendee@example.com")
    # An attendee has no AdminUser session even when holding a ticket.
    create(:ticket, order: paid_order, attendee_email: user.email)
    post checkin_path, params: { ticket_id: Ticket.last.id, date: }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "records per-attendee outcomes for success, duplicates, canceled and unknown tickets" do
    sign_in_admin(operator)
    good = create(:ticket, order: paid_order)
    duplicate = create(:ticket, order: paid_order)
    duplicate.check_in!(date)
    canceled = create(:ticket, order: paid_order, canceled_at: Time.current)

    submit([ good.id, duplicate.id, canceled.id, 999999999 ])

    expect(response).to have_http_status(:ok)
    results = response.parsed_body.fetch("results")
    expect(results.pluck("state")).to eq(%w[success warning error error])
    expect(good.reload.checked_in_at).to have_key(date)
    expect(canceled.reload.checked_in_at).to be_empty
    expect(CheckinAudit.pluck(:outcome)).to match_array(%w[success duplicate canceled not_found])
    expect(CheckinAudit.pluck(:admin_user_id).uniq).to eq([ operator.id ])
    expect(CheckinAudit.pluck(:source).uniq).to eq([ "batch" ])
    expect(response.body).not_to include(good.secret, good.claim_token)
  end

  it "deduplicates IDs and makes repeated requests harmless" do
    sign_in_admin(operator)
    ticket = create(:ticket, order: paid_order)
    submit([ ticket.id, ticket.id ])
    expect(response.parsed_body.fetch("results").size).to eq(1)
    original = ticket.reload.checked_in_at
    submit([ ticket.id ])
    expect(response.parsed_body.fetch("results").first.fetch("state")).to eq("warning")
    expect(ticket.reload.checked_in_at).to eq(original)
    expect(CheckinAudit.where(outcome: "success").count).to eq(1)
  end

  it "rejects missing confirmation, empty, malformed and oversized selections without mutation" do
    sign_in_admin(operator)
    ticket = create(:ticket, order: paid_order)
    [ [ [ ticket.id ], false ], [ [], true ], [ [ "all" ], true ], [ (1..51).to_a, true ], [ { all: true }, true ] ].each do |ids, confirmed|
      submit(ids, confirmed:)
      expect(response).to have_http_status(:unprocessable_content)
    end
    expect(ticket.reload.checked_in_at).to be_empty
    expect(CheckinAudit.count).to eq(0)
  end

  it "rejects dates outside the event without changing tickets" do
    sign_in_admin(operator)
    ticket = create(:ticket, order: paid_order)
    submit([ ticket.id ], day: "2026-10-12")
    expect(response).to have_http_status(:unprocessable_content)
    expect(ticket.reload.checked_in_at).to be_empty
  end

  it "does not admit pending, expired, or canceled orders, including zero-cost unconfirmed orders" do
    sign_in_admin(operator)
    tickets = %i[pending expired canceled].map { |status| create(:ticket, order: create(:order, status:, total_paise: 0), price_paise: 0) }
    submit(tickets.map(&:id))
    expect(response.parsed_body.fetch("results").pluck("state")).to eq(%w[error error error])
    expect(tickets.map { |ticket| ticket.reload.checked_in_at }).to eq([ {}, {}, {} ])
  end

  it "admits a legitimately completed complimentary ticket with no payment capture" do
    sign_in_admin(operator)
    order = create(:order, total_paise: 0)
    ticket = create(:ticket, order:, price_paise: 0)
    order.complete_comp!
    submit([ ticket.id ])
    expect(response.parsed_body.fetch("results").first.fetch("state")).to eq("success")
    expect(order.reload).to be_paid
  end

  it "enforces configured ticket-type days and excludes unpaid or wrong-day tickets from totals" do
    sign_in_admin(operator)
    type = create(:ticket_type, event_starts_on: "2026-10-10", event_ends_on: "2026-10-10")
    restricted = create(:ticket, order: paid_order, ticket_type: type)
    eligible = create(:ticket, order: paid_order)
    create(:ticket, attendee_name: "Unpaid")
    submit([ restricted.id, eligible.id ])
    expect(response.parsed_body.fetch("results").pluck("state")).to eq(%w[error success])
    get checkin_path(format: :json), params: { date: }
    expect(response.parsed_body.fetch("stats")).to include("total" => 1, "checked_in" => 1)
    expect(response.parsed_body.fetch("tickets").pluck("attendee_name")).not_to include("Unpaid")
    expect(response.body).not_to include(restricted.secret, eligible.secret)
    submit([ restricted.id ], day: "2026-10-10")
    expect(response.parsed_body.fetch("results").first.fetch("state")).to eq("success")
  end

  it "makes bounded search and selected-only review explicit" do
    sign_in_admin(operator)
    create_list(:ticket, 21, order: paid_order)
    get checkin_path(format: :json)
    expect(response.parsed_body.fetch("tickets").length).to eq(20)
    expect(response.parsed_body.fetch("more_results")).to be(true)
    get checkin_path, params: { ticket_ids: (1..51).to_a }
    expect(response).to have_http_status(:bad_request)
  end

  it "rolls back attendance if the success audit cannot be recorded" do
    ticket = create(:ticket, order: paid_order)
    allow(CheckinAudit).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    expect { ticket.check_in!(date, operator:) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(ticket.reload.checked_in_at).to be_empty
  end
end
