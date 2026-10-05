require "rails_helper"

RSpec.describe "Public DQOR programme v1", type: :request do
  let(:path) { "/api/public/v1/dqor/programme" }

  def speaker(**attributes)
    Speaker.create!({ name: "Public Speaker", published: true, status: :announced }.merge(attributes))
  end

  def talk(**attributes)
    Talk.create!({ title: "Public Session", published: true, starts_at: Time.utc(2026, 10, 8, 4, 50), ends_at: Time.utc(2026, 10, 8, 5) }.merge(attributes))
  end

  it "exposes only explicit public fields with stable string IDs and India-local timestamps" do
    person = speaker(title: "Public title", bio: "Public bio")
    session = talk(speaker: person, abstract: "Public abstract", room: "Main hall", track: "INTERNAL TRACK", speaker_bio: "INTERNAL NOTES")
    private_person = speaker(name: "PRIVATE PIPELINE", status: :yet_to_announce)
    private_link = talk(title: "Published but private speaker", speaker: private_person, speaker_name: "PRIVATE FALLBACK")
    hidden = speaker(name: "UNPUBLISHED SPEAKER", published: false)
    talk(title: "PRIVATE DRAFT", published: false, speaker: hidden)
    user = User.create!(email: "PRIVATE-ATTENDEE@example.test")
    ticket = create(:ticket, attendee_email: user.email)

    get path, params: { include_drafts: true, user_id: user.id }
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    body = response.parsed_body
    expect(body.fetch("schema_version")).to eq(1)
    expect(body.fetch("event")).to include("id" => "dqor-2026", "timezone" => "Asia/Kolkata", "start_date" => "2026-10-08", "end_date" => "2026-10-11")
    expect(body.fetch("speakers")).to eq([ { "id" => person.id.to_s, "name" => person.name, "title" => "Public title", "bio" => "Public bio", "profile_url" => "https://deccanqueenonrails.com/speakers/#{person.id}" } ])
    row = body.fetch("sessions").find { |item| item["id"] == session.id.to_s }
    expect(row).to include("starts_at" => "2026-10-08T10:20:00+05:30", "ends_at" => "2026-10-08T10:30:00+05:30", "local_date" => "2026-10-08", "speaker_id" => person.id.to_s)
    expect(body.fetch("sessions").find { |item| item["id"] == private_link.id.to_s }).to include("speaker_id" => nil, "speaker_name" => nil)
    expect(response.body).not_to include("PRIVATE", "INTERNAL", user.email, ticket.secret, ticket.claim_token)
    expect(response.headers["Set-Cookie"]).to be_nil
    expect(row.keys).to match_array(%w[id title abstract starts_at ends_at local_date speaker_id speaker_name room])
  end

  it "represents unscheduled and empty publications without inventing dates" do
    session = talk(starts_at: nil, ends_at: nil, speaker_name: "Legacy public name")
    get path
    expect(response.parsed_body.fetch("sessions").first).to include("starts_at" => nil, "ends_at" => nil, "local_date" => nil, "speaker_name" => "Legacy public name")
    session.update!(published: false)
    get path
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("sessions" => [], "speakers" => [])
  end

  it "revalidates unchanged content with a bodyless 304 and never relies on Last-Modified" do
    talk
    get path
    etag = response.headers.fetch("ETag")
    expect(response.headers["Cache-Control"]).to include("public", "max-age=0", "must-revalidate")
    expect(response.headers["Last-Modified"]).to be_nil
    get path, headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:not_modified)
    expect(response.body).to be_empty
    expect(response.headers["ETag"]).to eq(etag)
  end

  it "invalidates on approved edits without timestamp touches, unpublication and deletion" do
    session = talk
    get path
    etag = response.headers.fetch("ETag")
    old_version = response.parsed_body.fetch("content_version")
    original_timestamp = session.updated_at
    session.update_columns(ends_at: Time.utc(2026, 10, 8, 5, 2))
    expect(session.reload.updated_at).to eq(original_timestamp)
    get path, headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("content_version")).not_to eq(old_version)
    etag = response.headers.fetch("ETag")
    session.update_columns(published: false)
    get path, headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("sessions")).to eq([])
    session.update!(published: true)
    get path
    etag = response.headers.fetch("ETag")
    session.destroy!
    get path, headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("sessions")).to eq([])
  end

  it "does not let a timestamp-only validator hide an updated canonical programme" do
    session = talk
    session.update_columns(title: "Approved canonical correction")
    get path, headers: { "If-Modified-Since" => "Fri, 01 Jan 2100 00:00:00 GMT" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("sessions").first.fetch("title")).to eq("Approved canonical correction")
  end

  it "does not change the version for private edits, but invalidates for speaker withdrawals" do
    person = speaker
    session = talk(speaker: person)
    get path
    etag = response.headers.fetch("ETag")
    session.update!(track: "private edit")
    talk(title: "Private draft added", published: false)
    get path, headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:not_modified)
    person.update_columns(status: Speaker.statuses.fetch("on_hold"))
    get path, headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("speakers")).to eq([])
    expect(response.parsed_body.fetch("sessions").first).to include("speaker_id" => nil, "speaker_name" => nil)
  end

  it "returns a non-cacheable stable error instead of leaking database details or a false empty snapshot" do
    allow(PublicProgramme::Snapshot).to receive(:call).and_raise(ActiveRecord::ConnectionNotEstablished, "PRIVATE DATABASE SECRET")
    get path, headers: { "If-None-Match" => 'W/"old-version"' }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq("schema_version" => 1, "error" => { "code" => "programme_unavailable", "message" => "Programme temporarily unavailable. Try again later." })
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.headers["ETag"]).to be_nil
    expect(response.body).not_to include("PRIVATE", "sessions")
  end

  it "supports HEAD revalidation and ignores unrelated parameter/host variations in the public payload" do
    talk
    get path
    version = response.parsed_body.fetch("content_version")
    etag = response.headers.fetch("ETag")
    get path, params: { event_id: "private-tenant", ref: "tracking" }
    expect(response.parsed_body.fetch("content_version")).to eq(version)
    head path, headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:not_modified)
    expect(response.body).to be_empty
  end
end
