require "rails_helper"

RSpec.describe "Published owned events v1", type: :request do
  let!(:organization) { Organization.create!(name: "Public organizers", slug: "public-organizers") }
  let!(:event) { organization.events.create!(title: "Published meetup", slug: "meetup", status: :published, timezone: "Asia/Kolkata", starts_at: Time.utc(2026, 11, 6, 18, 45), ends_at: Time.utc(2026, 11, 6, 20)) }
  let(:detail_path) { public_event_path("hosted-event-#{event.id}") }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:public_events_enabled).and_return(true)
  end

  it "requires both default-off publication gates even for existing members" do
    [ [ false, true ], [ true, false ], [ false, false ] ].each do |platform, public_events|
      allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(platform)
      allow(Rails.configuration.x).to receive(:public_events_enabled).and_return(public_events)
      [ public_events_path, detail_path ].each do |path|
        get path
        expect(response).to have_http_status(:not_found)
        expect(response.headers["Cache-Control"]).to eq("no-store")
        expect(response.headers["ETag"]).to be_nil
        expect(response.body).not_to include(event.title)
      end
    end
  end

  it "exposes allowlisted public facts with opaque IDs and canonical local dates without creating sessions" do
    private_event = organization.events.create!(title: "PRIVATE DRAFT", slug: "draft")
    user = User.create!(email: "PRIVATE-OWNER@example.test")
    Membership.create!(organization: organization, user: user, role: :owner)
    ticket = create(:ticket, attendee_email: "PRIVATE-ATTENDEE@example.test")
    counts = [ Session.count, CheckinAudit.count, Ticket.count, Event.count, ticket.reload.checked_in_at ]

    get detail_path, params: { include_drafts: true, event_id: private_event.id, user_id: user.id }, headers: { "Authorization" => "Bearer invalid" }
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.keys).to match_array(%w[schema_version content_version event])
    expect(body.fetch("schema_version")).to eq(1)
    expect(body.fetch("content_version")).to match(/\A[a-f0-9]{64}\z/)
    row = body.fetch("event")
    expect(row.keys).to match_array(%w[id ownership title starts_at ends_at start_date end_date timezone organizer details_path])
    expect(row).to include("id" => "hosted-event-#{event.id}", "ownership" => "hosted_event", "starts_at" => "2026-11-07T00:15:00+05:30", "ends_at" => "2026-11-07T01:30:00+05:30", "start_date" => "2026-11-07", "end_date" => "2026-11-07", "timezone" => "Asia/Kolkata", "details_path" => published_event_path(organization.slug, event.slug))
    expect(row.fetch("organizer")).to eq("name" => organization.name, "slug" => organization.slug)
    expect(response.body).not_to include("PRIVATE", ticket.secret, ticket.claim_token, "password", "entitlement", "membership")
    expect(response.headers["Set-Cookie"]).to be_nil
    expect([ Session.count, CheckinAudit.count, Ticket.count, Event.count, ticket.reload.checked_in_at ]).to eq(counts)
  end

  it "reads only published records across organizations without confusing matching tenant slugs" do
    other = Organization.create!(name: "Other public host", slug: "other-host")
    second = other.events.create!(title: "Other published meetup", slug: event.slug, status: :published, starts_at: event.starts_at + 1.day, ends_at: event.ends_at + 1.day)
    organization.events.create!(title: "PRIVATE DRAFT", slug: "private")
    get public_events_path, params: { include_drafts: true, organization_id: organization.id }
    expect(response.parsed_body.fetch("events").map { |row| row.fetch("id") }).to eq([ "hosted-event-#{event.id}", "hosted-event-#{second.id}" ])
    expect(response.body).not_to include("PRIVATE")
    get public_event_path("hosted-event-#{second.id}")
    expect(response.parsed_body.fetch("event").fetch("organizer").fetch("slug")).to eq("other-host")
  end

  it "never maps legacy DQOR, external listings, drafts or malformed IDs into owned events" do
    draft = organization.events.create!(title: "PRIVATE DRAFT", slug: "private")
    [ "hosted-event-#{draft.id}", "hosted-event-999999999999999999", "hosted-event-9223372036854775807", "hosted-event-9223372036854775808", "hosted-event-0", "hosted-event--1", "hosted-event-999999999999999999999999", "dqor-2026", "external-1" ].each do |id|
      get public_event_path(id), headers: { "If-None-Match" => 'W/"old"' }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.fetch("error").fetch("code")).to eq("event_not_found")
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.headers["ETag"]).to be_nil
      expect(response.body).not_to include("PRIVATE")
    end
  end

  it "bounds catalog pages and orders by canonical start and stable ID" do
    24.times do |index|
      organization.events.create!(title: "Public #{index}", slug: "public-#{index}", status: :published, starts_at: event.starts_at + (index + 1).hours, ends_at: event.ends_at + (index + 1).hours)
    end
    get public_events_path
    first_ids = response.parsed_body.fetch("events").map { |row| row.fetch("id") }
    expect(first_ids.size).to eq(24)
    expect(response.parsed_body.fetch("pagination")).to eq("page" => 1, "per_page" => 24, "total" => 25)
    get public_events_path, params: { page: 2 }
    expect(response.parsed_body.fetch("events").size).to eq(1)
    expect(first_ids).not_to include(response.parsed_body.fetch("events").first.fetch("id"))
    get public_events_path, params: { page: 999999999 }
    expect(response.parsed_body.fetch("pagination").fetch("page")).to eq(1000)
    expect(response.parsed_body.fetch("events")).to eq([])
    get public_events_path, params: { page: [ "2" ] }
    expect(response.parsed_body.fetch("pagination").fetch("page")).to eq(1)
  end

  it "represents an empty publication authoritatively without synthesizing a legacy event" do
    event.update!(status: :draft)
    get public_events_path
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("events" => [], "pagination" => { "page" => 1, "per_page" => 24, "total" => 0 })
  end

  it "preserves timezone offsets across a daylight-saving transition" do
    event.update!(timezone: "Europe/London", starts_at: Time.utc(2026, 10, 25, 0, 30), ends_at: Time.utc(2026, 10, 25, 1, 30))
    get detail_path
    expect(response.parsed_body.fetch("event")).to include("starts_at" => "2026-10-25T01:30:00+01:00", "ends_at" => "2026-10-25T01:30:00+00:00", "start_date" => "2026-10-25", "end_date" => "2026-10-25", "timezone" => "Europe/London")
  end

  it "revalidates unchanged GET and HEAD snapshots with bodyless 304 and no timestamp validator" do
    [ public_events_path, detail_path ].each do |path|
      get path
      etag = response.headers.fetch("ETag")
      expect(response.headers["Cache-Control"]).to include("public", "max-age=0", "must-revalidate")
      expect(response.headers["Last-Modified"]).to be_nil
      get path, headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
      head path, headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
    end
  end

  it "invalidates on public edits without timestamp touches while keeping identity stable" do
    get detail_path
    etag = response.headers.fetch("ETag")
    identity = response.parsed_body.fetch("event").fetch("id")
    event.update_columns(title: "Approved correction", slug: "corrected")
    organization.update_columns(name: "Updated public host")
    get detail_path, headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("event")).to include("id" => identity, "title" => "Approved correction", "organizer" => { "name" => "Updated public host", "slug" => organization.slug })
    expect(response.headers.fetch("ETag")).not_to eq(etag)
  end

  it "withdraws an unpublished event instead of returning a stale 304" do
    get detail_path
    etag = response.headers.fetch("ETag")
    get public_events_path
    catalog_etag = response.headers.fetch("ETag")
    event.update_columns(status: "draft")
    get detail_path, headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:not_found)
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.headers["ETag"]).to be_nil
    get public_events_path, headers: { "If-None-Match" => catalog_etag }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("events")).to eq([])
  end

  it "does not change public versions for unpublished drafts or unrelated private records" do
    get public_events_path
    etag = response.headers.fetch("ETag")
    organization.events.create!(title: "Private addition", slug: "private")
    User.create!(email: "private@example.test")
    get public_events_path, headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:not_modified)
  end

  it "returns stable non-cacheable read errors without database details or a false empty snapshot" do
    allow(PublicEvents::Snapshot).to receive(:index).and_raise(ActiveRecord::ConnectionNotEstablished, "PRIVATE DATABASE")
    get public_events_path, headers: { "If-None-Match" => 'W/"old"' }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq("schema_version" => 1, "error" => { "code" => "events_unavailable", "message" => "Events temporarily unavailable. Try again later." })
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.headers["ETag"]).to be_nil
    expect(response.body).not_to include("PRIVATE")
  end
end
