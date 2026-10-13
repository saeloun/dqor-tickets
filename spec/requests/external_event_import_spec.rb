require "rails_helper"

RSpec.describe "External event import", type: :request do
  let!(:organization) { Organization.create!(name: "Pune Ruby Meetup", slug: "pune-ruby") }
  let!(:user) { User.create!(email: "importer@example.com") }
  let!(:membership) { Membership.create!(organization: organization, user: user, role: :owner) }
  let(:notes) { "Owner screenshot: October24,11:00–13:00; timezone unstated. Public description: October17; agenda begins09:30 and extends beyond13:00." }
  let(:attributes) do
    {
      title: "Ruby Meetup X AI Collective: Expert Insights & Hands-On Workshop", slug: "ruby-ai-october",
      starts_at: "2026-10-24T04:30:00Z", ends_at: "2026-10-24T07:30:00Z", timezone: "Asia/Kolkata",
      description: "Ruby developers, AI explorers and early-career developers meet for talks and workshops.",
      venue_name: "Pattern Technologies India Private Limited", venue_address: "Kalyani Nagar, Pune",
      source_url: "https://lu.ma/48awjqkg/?utm_source=poster#details", external_registration_url: "https://luma.com/48awjqkg",
      cfp_url: "https://forms.gle/6ZazdAJ2iJ8QFm7i6", topics: "Ruby, Ruby on Rails, AI", import_notes: notes
    }
  end

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
  end

  def create_import(overrides = {})
    post organizer_organization_events_path(organization), params: { event: attributes.merge(overrides) }
  end

  it "retains the approved calendar and metadata privately until explicit publication" do
    create_import
    expect(response).to have_http_status(:redirect)
    event = organization.events.find_by!(slug: attributes[:slug])
    expect(event).to have_attributes(status: "draft", starts_at: Time.utc(2026, 10, 24, 4, 30), ends_at: Time.utc(2026, 10, 24, 7, 30), timezone: "Asia/Kolkata", source_url: "https://luma.com/48awjqkg", import_notes: notes, venue_name: attributes[:venue_name])
    expect(TicketType.where(event_id: event.id)).to be_empty
    get published_event_path(organization.slug, event.slug)
    expect(response).to have_http_status(:not_found)
    get organizer_organization_event_path(organization, event)
    expect(response.body).to include(ERB::Util.html_escape(notes))
    post publish_organizer_organization_event_path(organization, event)
    get published_event_path(organization.slug, event.slug)
    expect(response.body).to include("10:00 AM", "1:00 PM", attributes[:venue_name], attributes[:external_registration_url])
    expect(response.body).not_to include(notes, "October17", "Import notes")
    allow(Rails.configuration.x).to receive(:public_events_enabled).and_return(true)
    get public_event_path("hosted-event-#{event.id}")
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("event")).not_to have_key("import_notes")
    expect(response.body).not_to include(notes, "October17", "Import notes")
  end
  it "reuses the scoped canonical source without overwriting metadata or publication" do
    create_import
    original = organization.events.find_by!(slug: attributes[:slug])
    original.update!(status: :published)
    before = original.attributes
    expect { create_import(title: "Changed title", slug: "different-slug", import_notes: "Overwrite") }.not_to change(Event, :count)
    expect(response).to redirect_to(organizer_organization_event_path(organization, original))
    expect(original.reload.attributes).to eq(before)
  end

  it "rejects conflicting timing without altering the existing record" do
    create_import
    original = organization.events.last
    before = original.attributes
    expect { create_import(starts_at: "2026-10-24T05:30:00Z") }.not_to change(Event, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.body).to include("different dates or timezone")
    expect(original.reload.attributes).to eq(before)
  end

  it "permits the same public source in another organization without revealing or altering it" do
    other = Organization.create!(name: "Other team", slug: "other-team")
    secret = other.events.create!(attributes.merge(title: "Private other title", import_notes: "Other private notes"))
    create_import
    expect(response).to have_http_status(:redirect)
    expect(organization.events.count).to eq(1)
    get organizer_organization_event_path(organization, organization.events.last)
    expect(response.body).not_to include("Private other title", "Other private notes")
    expect(secret.reload.title).to eq("Private other title")
    post organizer_organization_events_path(other), params: { event: attributes }
    expect(response).to have_http_status(:not_found)
  end

  it "keeps import creation behind the existing viewer and availability gates" do
    membership.update!(role: :viewer)
    expect { create_import }.not_to change(Event, :count)
    expect(response).to have_http_status(:forbidden)
    membership.update!(role: :owner)
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(false)
    expect { create_import }.not_to change(Event, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects unsafe links and escapes plain-text metadata on public pages" do
    expect { create_import(external_registration_url: "javascript:alert(1)") }.not_to change(Event, :count)
    expect(response).to have_http_status(:unprocessable_content)
    create_import(description: "<script>alert('unsafe')</script>")
    imported = organization.events.last
    imported.update!(status: :published)
    get published_event_path(organization.slug, imported.slug)
    expect(response.body).to include("&lt;script&gt;")
    expect(response.body).not_to include("<script>alert('unsafe')</script>")
  end
end
