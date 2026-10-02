require "rails_helper"

RSpec.describe "Free event pilot", type: :request do
  let!(:owner) { create(:user_for_free_pilot) }
  let!(:attendee) { create(:user_for_free_pilot, name: "Attendee One") }
  let!(:other_user) { create(:user_for_free_pilot) }
  let!(:organization) { Organization.create!(name: "First community", slug: "first") }
  let!(:other_organization) { Organization.create!(name: "Other community", slug: "other") }
  let!(:membership) { Membership.create!(user: owner, organization: organization, role: :owner) }
  let!(:event) { organization.events.create!(title: "Free meetup", slug: "meetup", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now) }
  let!(:other_event) { other_organization.events.create!(title: "Private other", slug: "other", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now) }
  let!(:type) { create(:ticket_type, event_id: event.id, price_paise: 0, capacity: 2, hidden: true, active: false, free_published_at: Time.current) }
  let!(:other_type) { create(:ticket_type, event_id: other_event.id, price_paise: 0, capacity: 2, hidden: true, active: false, free_published_at: Time.current) }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
  end

  def login(user)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
  end

  def register(user = attendee, type_id = type.id)
    login(user)
    post free_event_registration_path(organization.slug, event.slug), params: { ticket_type_id: type_id, user_id: other_user.id, email: other_user.email, total_paise: 1000 }
  end

  it "is unavailable when either gate is off, including for authorized users" do
    login(owner)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(false)
    get free_organizations_path
    expect(response).to have_http_status(:not_found)
    post free_event_registration_path(organization.slug, event.slug), params: { ticket_type_id: type.id }
    expect(response).to have_http_status(:not_found)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(false)
    get free_tickets_path
    expect(response).to have_http_status(:not_found)
  end

  it "requires an email-verified attendee session rather than a global admin" do
    sign_in_admin
    get free_organizations_path
    expect(response).to redirect_to(account_sign_in_path)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(owner)
    get free_organizations_path
    expect(response).to redirect_to(account_sign_in_path)
  end

  it "returns an attendee to their event after email verification without registering silently" do
    post free_event_registration_path(organization.slug, event.slug), params: { ticket_type_id: type.id }
    expect(response).to redirect_to(account_sign_in_path)
    login(attendee)
    expect(response).to redirect_to(published_event_path(organization.slug, event.slug))
    expect(Order.where(event_id: event.id)).to be_empty
  end

  it "lets a verified user create only their own new organization and owner membership" do
    login(owner)
    expect {
      post free_organizations_path, params: { organization: { name: "My community", slug: "mine", id: other_organization.id, user_id: other_user.id, role: "admin" } }
    }.to change(Organization, :count).by(1).and change(Membership, :count).by(1)
    created = Organization.find_by!(slug: "mine")
    expect(Membership.find_by!(organization: created, user: owner)).to be_owner
    expect(Membership.where(organization: other_organization)).to be_empty
  end

  it "registers once, ignores forged identity/money, and performs no payment, invoice, or email work" do
    expect(Razorpay::Order).not_to receive(:create)
    expect(Invoice).not_to receive(:issue_for!)
    expect { register }.to change(Order, :count).by(1).and change(Ticket, :count).by(1)
    order = Order.find_by!(event_id: event.id, user_id: attendee.id)
    expect(order).to have_attributes(email: attendee.email, status: "paid", total_paise: 0, razorpay_order_id: nil)
    expect(order.tickets.first).to have_attributes(event_id: event.id, attendee_email: attendee.email, price_paise: 0)
    expect(enqueued_jobs).to be_empty
    expect { register }.not_to change(Ticket, :count)
    get free_event_ticket_path(organization.slug, event.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("You’re registered", attendee.email)
    expect(response.body).not_to include(order.code, order.tickets.first.secret, order.tickets.first.claim_token)
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "rejects foreign inventory, draft events, and full or ended events" do
    register(attendee, other_type.id)
    expect(response).to have_http_status(:not_found)
    expect(Order.where(event_id: event.id)).to be_empty
    type.update!(capacity: 1)
    register
    register(other_user)
    expect(Order.where(event_id: event.id).count).to eq(1)
    expect(response).to redirect_to(published_event_path(organization.slug, event.slug))
    event.update!(status: :draft)
    register(other_user)
    expect(response).to have_http_status(:not_found)
    get published_event_path(organization.slug, event.slug)
    expect(response).to have_http_status(:not_found)
    event.update!(status: :published, starts_at: 2.days.ago, ends_at: 1.day.ago)
    register(other_user)
    expect(Order.where(event_id: event.id).count).to eq(1)
  end

  it "keeps ticket retrieval account-bound, including across organizations" do
    register
    login(other_user)
    get free_event_ticket_path(organization.slug, event.slug), params: { user_id: attendee.id }
    expect(response).to have_http_status(:not_found)
    get free_tickets_path
    expect(response.body).not_to include("Free meetup")
    login(attendee)
    get free_event_ticket_path(other_organization.slug, other_event.slug)
    expect(response).to have_http_status(:not_found)
  end

  it "isolates check-in and exports by role, organization, event, and ticket" do
    register
    ticket = Order.find_by!(event_id: event.id, user_id: attendee.id).tickets.first
    foreign = FreeEvents::Register.call(user: other_user, event_id: other_event.id, ticket_type_id: other_type.id).tickets.first
    login(owner)
    get free_event_attendees_path(organization, event, format: :csv)
    expect(response.body).to include(attendee.email)
    expect(response.body).not_to include(other_user.email, ticket.secret, ticket.order.code)
    post free_event_attendees_path(organization, event), params: { ticket_id: foreign.id }
    expect(response).to have_http_status(:not_found)
    expect(FreeCheckin.count).to eq(0)
    post free_event_attendees_path(organization, event), params: { ticket_id: ticket.id }
    expect(FreeCheckin.find_by!(ticket: ticket).operator).to eq(owner)
    expect { post free_event_attendees_path(organization, event), params: { ticket_id: ticket.id } }.not_to change(FreeCheckin, :count)
    get free_event_attendees_path(organization, other_event)
    expect(response).to have_http_status(:not_found)
    get free_event_attendees_path(other_organization, other_event, format: :csv)
    expect(response).to have_http_status(:not_found)
    %w[editor viewer].each do |role|
      membership.update!(role: role)
      get free_event_attendees_path(organization, event)
      expect(response).to have_http_status(:not_found)
      post free_event_attendees_path(organization, event), params: { ticket_id: ticket.id }
      expect(response).to have_http_status(:not_found)
      post free_event_inventory_path(organization, event), params: { ticket_type: { name: "No", capacity: 5 } }
      expect(response).to have_http_status(:not_found)
    end
    membership.destroy!
    get free_event_attendees_path(organization, event)
    expect(response).to have_http_status(:not_found)
  end

  it "publishes only zero-price hidden inventory for an owned published event" do
    login(owner)
    new_event = organization.events.create!(title: "Second", slug: "second", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now)
    post free_event_inventory_path(organization, new_event), params: { ticket_type: { name: "Free pass", capacity: 3, price_paise: 9900, event_id: other_event.id, active: true, hidden: false } }
    expect(response).to have_http_status(:redirect)
    pass = TicketType.find_by!(event_id: new_event.id)
    expect(pass).to have_attributes(price_paise: 0, capacity: 3, hidden: true, active: false)
    expect(pass.free_published_at).to be_present
    get published_event_path(organization.slug, new_event.slug)
    expect(response.body).to include("Register free")
  end
end
