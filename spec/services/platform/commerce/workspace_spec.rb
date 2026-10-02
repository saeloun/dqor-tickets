require "rails_helper"

RSpec.describe Platform::Commerce::Workspace do
  let!(:user) { User.create!(email: "owner@example.test") }
  let!(:organization) { Organization.create!(name: "One", slug: "one") }
  let!(:other_organization) { Organization.create!(name: "Two", slug: "two") }
  let!(:event) { organization.events.create!(title: "One", slug: "one") }
  let!(:sibling_event) { organization.events.create!(title: "Sibling", slug: "sibling") }
  let!(:other_event) { other_organization.events.create!(title: "Two", slug: "two") }
  let!(:membership) { Membership.create!(user: user, organization: organization, role: :owner) }
  let!(:type) { create(:ticket_type, event_id: event.id, price_paise: 0, hidden: true, active: false) }
  let!(:order) { create(:order, total_paise: 0, user_id: create(:user_for_free_pilot).id, event_id: event.id, email: "one@example.test", metadata: { private_billing_note: "PRIVATE" }) }
  let!(:ticket) { create(:ticket, event_id: event.id, ticket_type: type, order: order, attendee_email: "attendee-one@example.test") }
  let!(:other_type) { create(:ticket_type, event_id: other_event.id, price_paise: 0, hidden: true, active: false) }
  let!(:other_order) { create(:order, total_paise: 0, user_id: create(:user_for_free_pilot).id, event_id: other_event.id, email: "two@example.test") }
  let!(:other_ticket) { create(:ticket, event_id: other_event.id, ticket_type: other_type, order: other_order, attendee_email: "attendee-two@example.test") }
  let!(:legacy_ticket) { create(:ticket) }
  subject(:workspace) { described_class.new(user: user, organization_id: organization.id, event_id: event.id) }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:staged_commerce_enabled).and_return(true)
  end

  it "requires both flags on every operation" do
    allow(Rails.configuration.x).to receive(:staged_commerce_enabled).and_return(false)
    expect { workspace.ticket_types }.to raise_error(Platform::Commerce::Policy::Disabled)
    expect { workspace.create_ticket_type!(name: "Draft", price_paise: 0) }.to raise_error(Platform::Commerce::Policy::Disabled)
    allow(Rails.configuration.x).to receive(:staged_commerce_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(false)
    expect { workspace.orders_csv }.to raise_error(Platform::Commerce::Policy::Disabled)
  end

  it "does not accept global admin identity or anonymous access" do
    [ nil, create(:admin_user) ].each do |actor|
      denied = described_class.new(user: actor, organization_id: organization.id, event_id: event.id)
      expect { denied.orders }.to raise_error(Platform::Commerce::Policy::Forbidden)
    end
  end

  it "scopes lists and all lookups to exactly one event" do
    expect(workspace.ticket_types.map { |row| row.fetch("id") }).to eq([ type.id ])
    expect(workspace.orders.map { |row| row.fetch("id") }).to eq([ order.id ])
    expect(workspace.tickets.map { |row| row.fetch("id") }).to eq([ ticket.id ])
    expect(workspace.ticket_type(type.id).fetch("id")).to eq(type.id)
    expect(workspace.order_by_code(order.code).fetch("id")).to eq(order.id)
    expect(workspace.ticket(ticket.id).fetch("id")).to eq(ticket.id)
    [ other_type, legacy_ticket.ticket_type ].each do |foreign|
      expect { workspace.ticket_type(foreign.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
    [ other_order, legacy_ticket.order ].each do |foreign|
      expect { workspace.order_by_code(foreign.code) }.to raise_error(ActiveRecord::RecordNotFound)
    end
    [ other_ticket, legacy_ticket ].each do |foreign|
      expect { workspace.ticket(foreign.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
    sibling = create(:order, total_paise: 0, user_id: create(:user_for_free_pilot).id, event_id: sibling_event.id)
    expect { workspace.order_by_code(sibling.code) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "cannot substitute organization or event IDs, even when a user belongs to both organizations" do
    denied = described_class.new(user: user, organization_id: other_organization.id, event_id: other_event.id)
    expect { denied.orders }.to raise_error(ActiveRecord::RecordNotFound)
    Membership.create!(user: user, organization: other_organization, role: :owner)
    mismatched = described_class.new(user: user, organization_id: organization.id, event_id: other_event.id)
    expect { mismatched.ticket_types }.to raise_error(ActiveRecord::RecordNotFound)
    expect { mismatched.orders_csv }.to raise_error(ActiveRecord::RecordNotFound)
    expect { workspace.update_ticket_type!(other_type.id, name: "Hijacked") }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "creates only hidden inactive drafts and rejects ownership/publication mass assignment" do
    row = workspace.create_ticket_type!(name: "New pass", price_paise: 0)
    expect(row).to include("event_id" => event.id, "hidden" => true, "active" => false)
    %w[event_id ownership_key active hidden slug].each do |field|
      expect { workspace.create_ticket_type!({ name: "No", price_paise: 0, field => "1" }) }.to raise_error(described_class::UnsupportedAttributes)
      expect { workspace.update_ticket_type!(type.id, field => "1") }.to raise_error(described_class::UnsupportedAttributes)
    end
    expect(workspace.update_ticket_type!(type.id, name: "Updated").fetch("name")).to eq("Updated")
  end

  it "never changes a foreign event or legacy ticket type" do
    [ other_type, legacy_ticket.ticket_type ].each do |foreign|
      expect { workspace.update_ticket_type!(foreign.id, name: "No") }.to raise_error(ActiveRecord::RecordNotFound)
      expect(foreign.reload.name).not_to eq("No")
    end
  end

  it "does not leak another tenant, legacy records, financial snapshots, or bearer secrets in exports" do
    orders = CSV.parse(workspace.orders_csv, headers: true)
    attendees = CSV.parse(workspace.attendees_csv, headers: true)
    expect(orders.map { |row| row["id"] }).to eq([ order.id.to_s ])
    expect(attendees.map { |row| row["id"] }).to eq([ ticket.id.to_s ])
    combined = workspace.orders_csv + workspace.attendees_csv
    [ other_order.email, other_ticket.attendee_email, legacy_ticket.attendee_email,
      "PRIVATE", order.code, ticket.secret, ticket.claim_token ].each { |secret| expect(combined).not_to include(secret) }
    expect(orders.headers).not_to include("metadata", "gstin", "billing_address", "razorpay_order_id")
  end

  it "escapes spreadsheet formulas in exported user input" do
    order.update!(buyer_name: " =HYPERLINK(1)")
    ticket.update!(attendee_name: "@SUM(1)")
    expect(CSV.parse(workspace.orders_csv, headers: true).first["buyer_name"]).to eq("' =HYPERLINK(1)")
    expect(CSV.parse(workspace.attendees_csv, headers: true).first["attendee_name"]).to eq("'@SUM(1)")
  end

  it "returns immutable allowlisted snapshots, not live payment-capable records" do
    row = workspace.order_by_code(order.code)
    expect(row).to be_a(Hash)
    expect(row).to be_frozen
    expect(row.fetch("email")).to be_frozen
    expect(row.keys).to match_array(described_class::ORDER_FIELDS)
    expect(row).not_to respond_to(:create_razorpay_order!)
  end

  it "denies paid and complimentary issuance without invoking a merchant" do
    expect(Razorpay::Order).not_to receive(:create)
    expect(Order).not_to receive(:create!)
    [ 0, 10000 ].each do |amount|
      expect { workspace.create_order!(total_paise: amount) }.to raise_error(described_class::ProviderOnboardingRequired)
    end
  end

  it "refreshes revoked or demoted membership on an already-created workspace" do
    workspace.orders
    membership.update!(role: :viewer)
    expect { workspace.orders }.to raise_error(Platform::Commerce::Policy::Forbidden)
    expect { workspace.orders_csv }.to raise_error(Platform::Commerce::Policy::Forbidden)
    expect { workspace.update_ticket_type!(type.id, name: "No") }.to raise_error(Platform::Commerce::Policy::Forbidden)
    membership.destroy!
    expect { workspace.ticket_types }.to raise_error(ActiveRecord::RecordNotFound)
  end

  %w[viewer editor admin owner].each do |role|
    it "applies the #{role} role independently to inventory and attendee access" do
      membership.update!(role: role)
      expect(workspace.ticket_types.size).to eq(1)
      if role == "viewer"
        expect { workspace.update_ticket_type!(type.id, name: "Edit") }.to raise_error(Platform::Commerce::Policy::Forbidden)
      else
        expect(workspace.update_ticket_type!(type.id, name: "Edit").fetch("name")).to eq("Edit")
      end
      if %w[owner admin].include?(role)
        expect(workspace.orders.size).to eq(1)
        expect(CSV.parse(workspace.attendees_csv, headers: true).size).to eq(1)
      else
        expect { workspace.orders }.to raise_error(Platform::Commerce::Policy::Forbidden)
        expect { workspace.ticket(ticket.id) }.to raise_error(Platform::Commerce::Policy::Forbidden)
        expect { workspace.attendees_csv }.to raise_error(Platform::Commerce::Policy::Forbidden)
      end
    end
  end
end
