require "rails_helper"

RSpec.describe "Legacy rejects event-owned commerce", type: :request do
  let!(:user) { create(:user_for_free_pilot, name: "PRIVATE_FREE_ATTENDEE") }
  let!(:organization) { Organization.create!(name: "Private org", slug: "private") }
  let!(:event) { organization.events.create!(title: "Private event", slug: "private", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now) }
  let!(:type) { create(:ticket_type, event_id: event.id, name: "PRIVATE_FREE_TYPE", price_paise: 0, capacity: 3, hidden: true, active: false, free_published_at: Time.current) }
  let!(:order) { create(:order, :paid, event_id: event.id, user_id: user.id, total_paise: 0, email: user.email, buyer_name: user.name) }
  let!(:ticket) { create(:ticket, event_id: event.id, order: order, ticket_type: type, price_paise: 0, attendee_name: user.name, attendee_email: user.email) }

  it "denies public legacy order, claim, assignment, wallet and checkout lookups even with the pilot off" do
    [ order_path(order.code), ticket_claim_path(ticket.claim_token), apple_pass_path(ticket.secret), google_wallet_pass_path(ticket.secret) ].each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
      expect(response.body).not_to include(user.name, user.email)
    end
    patch assign_order_ticket_path(order.code, ticket.id), params: { ticket: { attendee_name: "Hijacked", attendee_email: "bad@example.test" } }
    expect(response).to have_http_status(:not_found)
    post orders_path, params: { checkout: { email: user.email, buyer_name: user.name, quantities: { type.id.to_s => 1 } } }
    expect(response).to have_http_status(:unprocessable_content)
    get tickets_store_path
    expect(response.body).not_to include(type.name)
    get root_path
    expect(response.body).not_to include(type.name)
  end

  it "excludes account, magic-link retrieval, marketing counts and exports" do
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
    get account_root_path
    expect(response.body).not_to include(type.name, order.code)
    expect(user.tickets).to be_empty
    expect(Ticket.confirmed).to be_empty
    expect(Ticket.broadcast_recipients).to be_empty
    expect(Order.orders_csv).not_to include(user.email, order.code)
    expect(Order.attendees_csv([ order ])).not_to include(user.email, ticket.secret)
    expect { post find_tickets_path, params: { email: user.email } }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
  end

  it "hides legacy admin lists, detail/edit/association lookup and staff check-in" do
    sign_in_admin
    %w[orders tickets ticket_types].zip([ order, ticket, type ]).each do |resource, record|
      get "/avo/resources/#{resource}"
      expect(response.body).not_to include(user.name, type.name)
      get "/avo/resources/#{resource}/#{record.id}"
      expect(response).to have_http_status(:not_found)
      get "/avo/resources/#{resource}/#{record.id}/edit"
      expect([ 404, 405 ]).to include(response.status)
    end
    get checkin_path, params: { q: user.email, date: "2026-10-08" }, as: :json
    expect(response.body).not_to include(user.name, user.email)
    get checkin_path, params: { ticket_ids: [ ticket.id ], date: "2026-10-08" }, as: :json
    expect(response.body).not_to include(user.name, user.email)
    post checkin_path, params: { secret: ticket.secret, date: "2026-10-08" }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(ticket.reload.checked_in_at).to eq({})
  end

  it "excludes private attendees from legacy association pickers and rejects forged attachments" do
    sign_in_admin
    legacy_order = create(:order)
    legacy_type = create(:ticket_type)
    [ [ "orders", legacy_order ], [ "ticket_types", legacy_type ] ].each do |resource, parent|
      path = "/avo/resources/#{resource}/#{parent.id}/tickets"
      get "#{path}/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("PRIVATE_FREE_ATTENDEE")
      get "/avo/avo_api/tickets/search", params: { q: "PRIVATE_FREE_ATTENDEE", via_association: "has_many", via_association_id: "tickets", via_reflection_class: parent.class.name, via_reflection_id: parent.id }
      expect(response.body).not_to include("PRIVATE_FREE_ATTENDEE")
      post path, params: { fields: { related_id: ticket.id } }
      expect(response).to have_http_status(:not_found)
      delete "#{path}/#{ticket.id}"
      expect(response).to have_http_status(:not_found)
      expect(ticket.reload).to have_attributes(order_id: order.id, ticket_type_id: type.id)
    end
    get "/avo/avo_api/orders/search", params: { q: user.email }
    expect(response.body).not_to include(order.code)
  end

  it "rejects owned tickets in native resolve, search and batch APIs" do
    allow(NativeStaffSession).to receive(:enabled?).and_return(true)
    allow(NativeStaffSession).to receive(:configured_dates).and_return([ "2026-10-08" ])
    operator = create(:admin_user, role: :desk, password: "password123")
    post "/api/staff/session", params: { email: operator.email, password: "password123" }, as: :json
    headers = { "Authorization" => "Bearer #{response.parsed_body.fetch('access_token')}" }
    post "/api/staff/checkins/resolve", params: { secret: ticket.secret, date: "2026-10-08" }, headers: headers.dup, as: :json
    expect(response).to have_http_status(:not_found)
    get "/api/staff/checkins", params: { q: user.email, date: "2026-10-08" }, headers: headers.dup, as: :json
    expect(response.body).not_to include(user.email, user.name)
    post "/api/staff/checkins/confirm", params: { ticket_ids: [ ticket.id ], confirmed: true, date: "2026-10-08" }, headers: headers.dup, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch("results").first.fetch("code")).to eq("not_found")
  end

  it "fails closed before legacy providers, mail, invoices, direct check-in and slots" do
    expect(Razorpay::Order).not_to receive(:create)
    expect(Razorpay::Order).not_to receive(:fetch)
    [ :create_razorpay_order!, :complete_comp!, :reconcile_payment!, :attach_documents!, :deliver_confirmation!, :deliver_order_link!, :resend_confirmation! ].each do |method|
      expect { order.public_send(method) }.to raise_error(ActiveRecord::RecordNotFound)
    end
    expect { order.refund_tickets!([ ticket.id ]) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { Invoice.issue_for!(order) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { OrderMailer.confirmation(order).deliver_now }.to raise_error(ActiveRecord::RecordNotFound)
    expect { ticket.check_in!(Date.new(2026, 10, 8)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { ticket.attach_pdf! }.to raise_error(ActiveRecord::RecordNotFound)
    expect { GoogleWalletGenerator.new(ticket) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { PkpassGenerator.new(ticket) }.to raise_error(ActiveRecord::RecordNotFound)
    operator = create(:admin_user)
    expect(Checkins::Record.call(ticket: ticket, date: Date.new(2026, 10, 8), operator: operator, source: "manual")[:code]).to eq("not_found")
    expect { EventSlots::Redeem.call(slot: nil, ticket: ticket, operator: operator, request_key: SecureRandom.uuid) }.to raise_error(EventSlots::Redeem::Rejected, "Ticket not found")
    expect(enqueued_jobs).to be_empty
  end
end
