require "rails_helper"

RSpec.describe "Organizer events", type: :request do
  let!(:organization) { Organization.create!(name: "One", slug: "one") }
  let!(:other_organization) { Organization.create!(name: "Two", slug: "two") }
  let!(:user) { User.create!(email: "organizer@example.com") }
  let!(:membership) { Membership.create!(organization: organization, user: user, role: :owner) }
  let!(:event) { organization.events.create!(title: "Private draft", slug: "draft") }
  let!(:other_event) { other_organization.events.create!(title: "Other secret", slug: "draft") }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
  end

  def login
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
  end

  it "is unavailable by default even to a member" do
    login
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(false)
    get organizer_organization_events_path(organization)
    expect(response).to have_http_status(:not_found)
    get published_event_path(organization.slug, event.slug)
    expect(response).to have_http_status(:not_found)
  end

  it "requires attendee sign-in" do
    get organizer_organization_events_path(organization)
    expect(response).to redirect_to(account_sign_in_path)
  end

  it "does not treat an administrator session as organization membership" do
    sign_in_admin
    get organizer_organization_events_path(organization)
    expect(response).to redirect_to(account_sign_in_path)
  end

  it "lists only the member's organization events" do
    login
    get organizer_organization_events_path(organization)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Private draft")
    expect(response.body).not_to include("Other secret")
    get organizer_organization_events_path(other_organization)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects cross-organization reads, edits, and publication even with membership in both" do
    Membership.create!(organization: other_organization, user: user, role: :owner)
    login
    get organizer_organization_event_path(organization, other_event)
    expect(response).to have_http_status(:not_found)
    get edit_organizer_organization_event_path(organization, other_event)
    expect(response).to have_http_status(:not_found)
    patch organizer_organization_event_path(organization, other_event), params: { event: { title: "Hijacked" } }
    expect(response).to have_http_status(:not_found)
    post publish_organizer_organization_event_path(organization, other_event)
    expect(response).to have_http_status(:not_found)
    expect(other_event.reload).to have_attributes(title: "Other secret", status: "draft")
  end

  it "rejects writes to organizations without a membership" do
    login
    post organizer_organization_events_path(other_organization), params: { event: { title: "Hijacked", slug: "hijacked" } }
    expect(response).to have_http_status(:not_found)
    patch organizer_organization_event_path(other_organization, other_event), params: { event: { title: "Hijacked" } }
    expect(response).to have_http_status(:not_found)
    post publish_organizer_organization_event_path(other_organization, other_event)
    expect(response).to have_http_status(:not_found)
  end

  it "creates a draft without accepting tenant or status mass assignment" do
    login
    post organizer_organization_events_path(organization), params: { event: { title: "New", slug: "new", organization_id: other_organization.id, status: "published" } }
    expect(response).to have_http_status(:redirect)
    expect(organization.events.find_by!(slug: "new")).to be_draft
  end

  it "cannot move an event through update" do
    login
    patch organizer_organization_event_path(organization, event), params: { event: { title: "Updated", organization_id: other_organization.id, status: "published" } }
    expect(response).to have_http_status(:redirect)
    expect(event.reload).to have_attributes(title: "Updated", organization_id: organization.id, status: "draft")
  end

  it "allows viewers to read but not write" do
    membership.update!(role: :viewer)
    login
    get organizer_organization_event_path(organization, event)
    expect(response).to have_http_status(:ok)
    get new_organizer_organization_event_path(organization)
    expect(response).to have_http_status(:forbidden)
    post organizer_organization_events_path(organization), params: { event: { title: "No", slug: "no" } }
    expect(response).to have_http_status(:forbidden)
    patch organizer_organization_event_path(organization, event), params: { event: { title: "No" } }
    expect(response).to have_http_status(:forbidden)
    post publish_organizer_organization_event_path(organization, event)
    expect(response).to have_http_status(:forbidden)
  end

  it "revokes access on the next request after membership removal" do
    login
    membership.destroy!
    get organizer_organization_event_path(organization, event)
    expect(response).to have_http_status(:not_found)
  end

  it "keeps drafts private and publishes only after complete valid details" do
    get published_event_path(organization.slug, event.slug)
    expect(response).to have_http_status(:not_found)
    login
    post publish_organizer_organization_event_path(organization, event)
    expect(response).to have_http_status(:unprocessable_content)
    expect(event.reload).to be_draft
    patch organizer_organization_event_path(organization, event), params: { event: { starts_at: "2026-11-01T09:00", ends_at: "2026-11-01T17:00", timezone: "Asia/Kolkata" } }
    post publish_organizer_organization_event_path(organization, event)
    expect(response).to have_http_status(:redirect)
    expect(event.reload).to be_published
    get published_event_path(organization.slug, event.slug)
    expect(response).to have_http_status(:ok)
    get published_event_path(other_organization.slug, other_event.slug)
    expect(response).to have_http_status(:not_found)
  end
end
