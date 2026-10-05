require "rails_helper"

RSpec.describe "Organizer operations", type: :request do
  let!(:organization) { Organization.create!(name: "One", slug: "ops-one") }
  let!(:other_organization) { Organization.create!(name: "Two", slug: "ops-two") }
  let!(:user) { User.create!(email: "ops@example.com") }
  let!(:membership) { Membership.create!(organization: organization, user: user, role: :owner) }
  let!(:event) { organization.events.create!(title: "Event one", slug: "one") }
  let!(:sibling) { organization.events.create!(title: "Sibling", slug: "sibling") }
  let!(:foreign_event) { other_organization.events.create!(title: "Foreign", slug: "foreign") }
  let!(:contact) { Operations::BusinessContact.create!(event: event, name: "Approved partner", email: "private@example.com", outreach_approved: true) }
  let!(:deal) { Operations::SponsorDeal.create!(event: event, business_contact: contact, title: "Gold", stage: "committed", contribution: "cash", amount_paise: 10000) }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:organizer_operations_enabled).and_return(true)
  end

  def login
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
  end

  def dashboard(org = organization, selected_event = event)
    organizer_organization_event_operations_path(org, selected_event)
  end

  def create_record(kind, attributes)
    post organizer_organization_event_operation_records_path(organization, event, kind), params: { record: attributes }
  end

  def receipt(amount, kind = "receipt")
    create_record("entries", sponsor_deal_id: deal.id, kind: kind, amount_paise: amount, occurred_on: "2026-10-02", reference: "manual-test")
  end

  it "requires both flags before authentication" do
    %i[organizer_platform_enabled organizer_operations_enabled].each do |flag|
      allow(Rails.configuration.x).to receive(flag).and_return(false)
      get dashboard
      expect(response).to have_http_status(:not_found)
      create_record("contacts", name: "Blocked")
      expect(response).to have_http_status(:not_found)
      allow(Rails.configuration.x).to receive(flag).and_return(true)
    end
  end

  it "requires attendee membership and never accepts an admin session as a bypass" do
    get dashboard
    expect(response).to redirect_to(account_sign_in_path)
    sign_in_admin
    get dashboard
    expect(response).to redirect_to(account_sign_in_path)
  end

  it "denies editor/viewer reads, exports, drafts and writes, and immediately enforces revocation" do
    login
    %w[editor viewer].each do |role|
      membership.update!(role: role)
      get dashboard
      expect(response).to have_http_status(:forbidden)
      get dashboard + ".csv"
      expect(response).to have_http_status(:forbidden)
      get organizer_organization_event_operation_draft_path(organization, event, contact)
      expect(response).to have_http_status(:forbidden)
      receipt(100)
      expect(response).to have_http_status(:forbidden)
    end
    membership.destroy!
    get dashboard
    expect(response).to have_http_status(:not_found)
  end

  it "scopes reads and all related IDs to both organization and selected event" do
    Membership.create!(organization: other_organization, user: user, role: :owner)
    login
    [ sibling, foreign_event ].each do |outside|
      foreign_contact = Operations::BusinessContact.create!(event: outside, name: "Secret", outreach_approved: true)
      foreign_deal = Operations::SponsorDeal.create!(event: outside, business_contact: foreign_contact, title: "Secret", stage: "committed", contribution: "cash", amount_paise: 10000)
      foreign_vendor = Operations::VendorEngagement.create!(event: outside, business_contact: foreign_contact, title: "Secret", amount_paise: 10000)
      task = Operations::FulfillmentTask.create!(event: outside, sponsor_deal: foreign_deal, title: "Secret")
      create_record("deals", business_contact_id: foreign_contact.id, title: "Attack", amount_paise: 10, stage: "committed", contribution: "cash")
      expect(response).to have_http_status(:not_found)
      create_record("entries", sponsor_deal_id: foreign_deal.id, kind: "receipt", amount_paise: 10, occurred_on: "2026-10-02", reference: "Attack")
      expect(response).to have_http_status(:not_found)
      create_record("entries", vendor_engagement_id: foreign_vendor.id, kind: "expense", amount_paise: 10, occurred_on: "2026-10-02", reference: "Attack")
      expect(response).to have_http_status(:not_found)
      create_record("tasks", sponsor_deal_id: foreign_deal.id, title: "Attack")
      expect(response).to have_http_status(:not_found)
      patch organizer_organization_event_complete_operation_task_path(organization, event, task)
      expect(response).to have_http_status(:not_found)
      patch organizer_organization_event_commit_operation_deal_path(organization, event, foreign_deal)
      expect(response).to have_http_status(:not_found)
      get organizer_organization_event_operation_draft_path(organization, event, foreign_contact)
      expect(response).to have_http_status(:not_found)
    end
    get dashboard(organization, foreign_event)
    expect(response).to have_http_status(:not_found)
    get dashboard
    expect(response.body).not_to include("Secret")
  end

  it "persists the contact, pledge, commitment, installments, refunds and deliverable flow with audits" do
    login
    create_record("contacts", name: "New partner", event_id: foreign_event.id, organization_id: other_organization.id)
    expect(response).to have_http_status(:redirect)
    new_contact = Operations::BusinessContact.last
    expect(new_contact.event).to eq(event)
    create_record("deals", business_contact_id: new_contact.id, title: "New deal", amount_paise: 10000, stage: "pledged", contribution: "cash")
    new_deal = Operations::SponsorDeal.last
    patch organizer_organization_event_commit_operation_deal_path(organization, event, new_deal)
    expect(new_deal.reload.stage).to eq("committed")
    receipt(3000)
    expect(response).to have_http_status(:redirect)
    receipt(2000)
    receipt(1000, "refund")
    expect(deal.cash_received_paise).to eq(4000)
    create_record("tasks", sponsor_deal_id: deal.id, title: "Giveaway handover", completed: true)
    task = Operations::FulfillmentTask.last
    expect(task).not_to be_completed
    patch organizer_organization_event_complete_operation_task_path(organization, event, task)
    expect(task.reload).to be_completed
    expect(Operations::AuditLog.where(event: event).count).to eq(8)
    expect(Operations::AuditLog.pluck(:user_id).uniq).to eq([ user.id ])
    get dashboard
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Giveaway handover", "4000", "AI generation is disabled")
    expect(response.headers["Cache-Control"]).to eq("no-store")
  end

  it "allows admins and records vendor partial expenses and returns" do
    membership.update!(role: :admin)
    login
    create_record("vendors", business_contact_id: contact.id, title: "AV rental", amount_paise: 9000)
    vendor = Operations::VendorEngagement.last
    %w[expense expense_refund].each do |kind|
      create_record("entries", vendor_engagement_id: vendor.id, kind: kind, amount_paise: 2000, occurred_on: "2026-10-02", reference: "AV")
      expect(response).to have_http_status(:redirect)
    end
    expect(vendor.cash_paid_paise).to eq(0)
  end

  it "rejects invalid paise, overpayments, excess refunds, pledges and in-kind receipts without audits" do
    login
    [ 0, -1, "1.5", 10001 ].each do |amount|
      receipt(amount)
      expect(response).to have_http_status(:unprocessable_content)
    end
    receipt(1, "refund")
    expect(response).to have_http_status(:unprocessable_content)
    deal.update!(stage: "pledged")
    receipt(100)
    expect(response).to have_http_status(:unprocessable_content)
    deal.update!(stage: "committed", contribution: "in_kind")
    receipt(100)
    expect(response).to have_http_status(:unprocessable_content)
    expect(Operations::ManualEntry.count).to eq(0)
    expect(Operations::AuditLog.count).to eq(0)
  end

  it "exports only allowlisted typed cash fields and renders drafts only after explicit approval" do
    login
    receipt(100)
    get dashboard + ".csv"
    expect(response).to have_http_status(:ok)
    expect(CSV.parse(response.body).first).to eq(%w[id kind amount_paise occurred_on sponsor_deal_id vendor_engagement_id])
    expect(response.body).not_to include("private@example.com", "manual-test", "Approved partner")
    get organizer_organization_event_operation_draft_path(organization, event, contact)
    expect(response.body).to include("Approved partner", "Event one", "Nothing has been sent")
    contact.update!(outreach_approved: false)
    get organizer_organization_event_operation_draft_path(organization, event, contact)
    expect(response).to have_http_status(:unprocessable_content)
  end
end
