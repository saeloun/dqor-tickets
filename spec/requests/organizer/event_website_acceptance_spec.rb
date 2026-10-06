require "rails_helper"

RSpec.describe "Event website acceptance", type: :request do
  let!(:organization) { Organization.create!(name: "Synthetic Ruby Community", slug: "website-community") }
  let!(:other_organization) { Organization.create!(name: "Other Synthetic Community", slug: "website-other") }
  let!(:owner) { create(:user_for_free_pilot, name: "Synthetic Website Organizer") }
  let!(:membership) { Membership.create!(organization:, user: owner, role: :owner) }
  let!(:event) { organization.events.create!(title: "Synthetic Tenant Conference", slug: "conference", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now, timezone: "Asia/Kolkata") }
  let!(:other_event) { other_organization.events.create!(title: "Other Tenant Conference", slug: "conference", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now) }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
  end

  def login(user = owner)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token:)
  end

  def website_path(organization_record = organization, event_record = event)
    organizer_organization_event_website_path(organization_record, event_record)
  end

  def setting
    EventWebsiteSetting.find_by!(event:)
  end

  def draft_params(**changes)
    saved = EventWebsiteSetting.find_by(event:)
    values = saved ? saved.draft : EventWebsites::Configuration.defaults.to_h
    values = values.except("version", "assets")
    %w[programme sponsors].each { |key| values.delete(key) if values[key] == [] }
    values.merge("lock_version" => saved&.lock_version || 0).merge(changes.stringify_keys)
  end

  def save_draft(**changes)
    patch website_path, params: { website: draft_params(**changes) }
  end

  def publish
    post publish_organizer_organization_event_website_path(organization, event), params: { confirmed: "1", lock_version: setting.reload.lock_version }
  end

  def restore
    post restore_organizer_organization_event_website_path(organization, event), params: { confirmed: "1", lock_version: setting.reload.lock_version }
  end

  def with_upload(bytes = ChunkyPNG::Image.new(16, 16, ChunkyPNG::Color.rgb(32, 80, 120)).to_blob, content_type: "image/png")
    Tempfile.create([ "synthetic-website", ".img" ]) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      yield Rack::Test::UploadedFile.new(file.path, content_type)
    end
  end

  def private_asset_path(image_id, organization_record = organization, event_record = event)
    asset_organizer_organization_event_website_path(organization_record, event_record, asset_id: image_id)
  end

  def public_asset_path(image_id, organization_record = organization, event_record = event)
    event_website_asset_path(organization_record.slug, event_record.slug, image_id)
  end

  def all_mutations
    patch website_path, params: { website: draft_params(summary: "Unauthorized replacement") }
    yield
    [ publish_organizer_organization_event_website_path(organization, event), restore_organizer_organization_event_website_path(organization, event) ].each do |path|
      post path, params: { confirmed: "1", lock_version: 0 }
      yield
    end
  end

  it "keeps the existing platform gate and avoids creating settings on authorized reads" do
    login
    get website_path
    expect(response).to have_http_status(:ok)
    get preview_organizer_organization_event_website_path(organization, event)
    expect(response).to have_http_status(:ok)
    expect(EventWebsiteSetting.count).to eq(0)
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(false)
    get website_path
    expect(response).to have_http_status(:not_found)
    all_mutations { expect(response).to have_http_status(:not_found) }
    expect(EventWebsiteSetting.count).to eq(0)
  end

  it "requires an attendee session for every private endpoint without creating settings" do
    [ website_path, preview_organizer_organization_event_website_path(organization, event), private_asset_path(1) ].each do |path|
      get path
      expect(response).to redirect_to(account_sign_in_path)
    end
    all_mutations { expect(response).to redirect_to(account_sign_in_path) }
    expect(EventWebsiteSetting.count).to eq(0)
  end

  it "grants no tenant permission from a global staff administrator session" do
    sign_in_admin
    get website_path
    expect(response).to redirect_to(account_sign_in_path)
    all_mutations { expect(response).to redirect_to(account_sign_in_path) }
    expect(EventWebsiteSetting.count).to eq(0)
  end

  %i[owner admin editor].each do |role|
    it "allows the freshly authorized #{role} to save, publish, and restore" do
      membership.update!(role:)
      login
      save_draft(summary: "First publication")
      expect(response).to redirect_to(website_path)
      publish
      expect(response).to redirect_to(website_path)
      save_draft(summary: "Second publication")
      publish
      restore
      expect(response).to redirect_to(website_path)
      expect(setting.reload.published.fetch("summary")).to eq("First publication")
      expect(setting.draft.fetch("summary")).to eq("Second publication")
      expect(setting.updated_by).to eq(owner)
      expect(setting.published_by).to eq(owner)
    end
  end

  it "permits viewer previews and private images but never viewer mutations" do
    login
    with_upload { |upload| save_draft(logo: upload, summary: "Private owner draft") }
    image_id = setting.reload.draft.fetch("assets").fetch("logo")
    original = setting.attributes.slice("draft", "published", "previous_published", "lock_version")
    membership.update!(role: :viewer)
    [ website_path, preview_organizer_organization_event_website_path(organization, event), private_asset_path(image_id) ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
    all_mutations { expect(response).to have_http_status(:forbidden) }
    expect(setting.reload.attributes.slice(*original.keys)).to eq(original)
  end

  it "checks revoked membership fresh on reads, previews, images, and all mutations" do
    login
    with_upload { |upload| save_draft(logo: upload, summary: "Private owner draft") }
    image_id = setting.reload.draft.fetch("assets").fetch("logo")
    original = setting.attributes.slice("draft", "published", "lock_version")
    membership.destroy!
    [ website_path, preview_organizer_organization_event_website_path(organization, event), private_asset_path(image_id) ].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
    all_mutations { expect(response).to have_http_status(:not_found) }
    expect(setting.reload.attributes.slice(*original.keys)).to eq(original)
  end

  it "rejects another organization and a foreign event even with memberships in both" do
    Membership.create!(organization: other_organization, user: owner, role: :owner)
    login
    save_draft(summary: "Owned content")
    original = setting.attributes.slice("draft", "published", "lock_version")
    get website_path(organization, other_event)
    expect(response).to have_http_status(:not_found)
    get preview_organizer_organization_event_website_path(organization, other_event)
    expect(response).to have_http_status(:not_found)
    patch website_path(organization, other_event), params: { website: draft_params(summary: "Foreign edit") }
    expect(response).to have_http_status(:not_found)
    [ publish_organizer_organization_event_website_path(organization, other_event), restore_organizer_organization_event_website_path(organization, other_event) ].each do |path|
      post path, params: { confirmed: "1", lock_version: 0 }
      expect(response).to have_http_status(:not_found)
    end
    expect(setting.reload.attributes.slice(*original.keys)).to eq(original)
    Membership.find_by!(organization: other_organization, user: owner).destroy!
    get website_path(other_organization, other_event)
    expect(response).to have_http_status(:not_found)
  end

  it "isolates public publication from saved drafts and requires explicit current-version confirmation" do
    login
    save_draft(summary: "Saved private proposal")
    get published_event_path(organization.slug, event.slug)
    expect(response.body).not_to include("Saved private proposal")
    get preview_organizer_organization_event_website_path(organization, event)
    expect(response.body).to include("Saved private proposal")
    expect(response.headers["Cache-Control"]).to include("no-store")
    post publish_organizer_organization_event_website_path(organization, event), params: { lock_version: setting.reload.lock_version }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(setting.reload.published).to be_nil
    publish
    expect(response).to redirect_to(website_path)
    save_draft(summary: "Unpublished later proposal")
    get published_event_path(organization.slug, event.slug)
    expect(response.body).to include("Saved private proposal")
    expect(response.body).not_to include("Unpublished later proposal")
    get preview_organizer_organization_event_website_path(organization, event)
    expect(response.body).to include("Unpublished later proposal")
  end

  it "serves only current event-owned published images publicly and retains private rollback images" do
    login
    with_upload { |upload| save_draft(logo: upload, summary: "First") }
    first_id = setting.reload.draft.fetch("assets").fetch("logo")
    get public_asset_path(first_id)
    expect(response).to have_http_status(:not_found)
    get private_asset_path(first_id)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/webp")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    publish
    get public_asset_path(first_id)
    expect(response).to have_http_status(:ok)
    with_upload { |upload| save_draft(logo: upload, summary: "Second") }
    second_id = setting.reload.draft.fetch("assets").fetch("logo")
    get public_asset_path(second_id)
    expect(response).to have_http_status(:not_found)
    get public_asset_path(first_id, other_organization, other_event)
    expect(response).to have_http_status(:not_found)
    sibling = organization.events.create!(title: "Sibling", slug: "sibling", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now)
    get public_asset_path(first_id, organization, sibling)
    expect(response).to have_http_status(:not_found)
    get private_asset_path(first_id, organization, sibling)
    expect(response).to have_http_status(:not_found)
    publish
    get public_asset_path(first_id)
    expect(response).to have_http_status(:not_found)
    get private_asset_path(first_id)
    expect(response).to have_http_status(:ok)
    restore
    get public_asset_path(first_id)
    expect(response).to have_http_status(:ok)
    get public_asset_path(second_id)
    expect(response).to have_http_status(:not_found)
    event.update!(status: :draft)
    get public_asset_path(first_id)
    expect(response).to have_http_status(:not_found)
    expect(setting.reload.assets.exists?(first_id)).to be(true)
    expect(setting.assets.exists?(second_id)).to be(true)
  end

  it "rejects stale save, publish, and restore without overwriting any snapshots or images" do
    login
    save_draft(summary: "First")
    publish
    save_draft(summary: "Second")
    publish
    stale = setting.reload.lock_version
    save_draft(summary: "New draft")
    original = setting.reload.attributes.slice("draft", "published", "previous_published", "lock_version")
    with_upload { |upload| save_draft(lock_version: stale, logo: upload, summary: "Lost stale save") }
    expect(response).to have_http_status(:conflict)
    expect(setting.reload.assets.count).to eq(0)
    [ publish_organizer_organization_event_website_path(organization, event), restore_organizer_organization_event_website_path(organization, event) ].each do |path|
      post path, params: { confirmed: "1", lock_version: stale }
      expect(response).to have_http_status(:conflict)
    end
    expect(setting.reload.attributes.slice(*original.keys)).to eq(original)
  end

  it "rejects invalid schema and a foreign managed asset without partial changes" do
    login
    save_draft(summary: "Preserved saved draft")
    publish
    foreign = EventWebsiteSetting.create!(event: other_event, draft: EventWebsites::Configuration.defaults.to_h)
    with_upload do |upload|
      attributes = EventBrandingAsset.normalized_upload(upload)
      foreign_asset = foreign.assets.create!(attributes)
      [
        { css: "body{display:none}" },
        { script: "alert(1)" },
        { hero_url: "https://external.example/image.png" },
        { event_id: other_event.id },
        { accent: "red;background:url(https://external.example)" },
        { font: "External Font" },
        { sections: %w[about about] },
        { navigation: [ "https://external.example" ] },
        { summary: "x" * 301 },
        { about: "<script>synthetic_website_marker()</script>" },
        { programme: [ "" ] },
        { sponsors: [ "" ] },
        { programme: [ { time: "09:00", title: "Talk", speaker: "Speaker", html: "<script>" } ] },
        { sponsors: [ { name: "Sponsor", tier: "Community", event_id: other_event.id } ] },
        { assets: { logo: foreign_asset.id } },
        { lock_version: "" }
      ].each do |changes|
        original = setting.reload.attributes.slice("draft", "published", "previous_published", "lock_version")
        save_draft(**changes)
        expect(response).to have_http_status(:unprocessable_entity), changes.inspect
        expect(setting.reload.attributes.slice(*original.keys)).to eq(original)
        expect(setting.assets.count).to eq(0)
      end
    end
  end

  it "rejects unsafe uploads atomically even alongside a valid new logo" do
    login
    save_draft(summary: "Preserved snapshot")
    publish
    original = setting.reload.attributes.slice("draft", "published", "lock_version")
    [ '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', "\x89PNG\r\n\x1a\ninvalid".b, "x" * (1.megabyte + 1) ].each do |bytes|
      with_upload do |valid|
        with_upload(bytes) { |invalid| save_draft(logo: valid, cover: invalid) }
      end
      expect(response).to have_http_status(:unprocessable_entity)
      expect(setting.reload.attributes.slice(*original.keys)).to eq(original)
      expect(setting.assets.count).to eq(0)
    end
  end

  it "renders canonical tenant identity, escaped manual content, and only tenant free registration" do
    Talk.create!(title: "Global DQOR Talk Must Stay Private", abstract: "Global abstract", speaker_name: "Global Speaker", published: true)
    Sponsor.create!(name: "Global DQOR Sponsor Must Stay Private", published: true)
    pass = create(:ticket_type, event_id: event.id, price_paise: 0, hidden: true, active: false, capacity: 2, free_published_at: Time.current)
    login
    save_draft(summary: "Tenant-only summary", about: 'Synthetic & "community"', venue_name: "Synthetic Community Hall", programme: [ { "time" => "09:00", "title" => "Tenant Manual Talk", "speaker" => "Tenant Speaker" } ], sponsors: [ { "name" => "Tenant Sponsor", "tier" => "Community" } ])
    publish
    get published_event_path(organization.slug, event.slug)
    document = response.parsed_body
    expect(document.at_css("title").text).to include(event.title, organization.name)
    expect(document.at_css("header").text).to include(event.title)
    expect(document.at_css("header").text).not_to include("Deccan Queen on Rails")
    expect(document.text).to include(event.title, "Tenant-only summary", "Synthetic Community Hall", "Tenant Manual Talk", "Tenant Sponsor")
    expect(document.text).not_to include("Global DQOR Talk Must Stay Private", "Global DQOR Sponsor Must Stay Private")
    expect(document.css("script").map(&:text).join).not_to include("synthetic_website_marker")
    expect(response.body).to include("Synthetic &amp; &quot;community&quot;")
    expect(document.css("form").map { |form| form["action"] }).to include(free_event_registration_path(organization.slug, event.slug))
    expect(response.body).to include(pass.id.to_s)
    get published_event_path(other_organization.slug, other_event.slug)
    expect(response.body).not_to include("Tenant-only summary", "Tenant Manual Talk", "Tenant Sponsor")
    get root_path
    expect(response.body).not_to include("Tenant-only summary", "Tenant Manual Talk", "Tenant Sponsor")
    expect(EventBrandingSetting.count).to eq(0)
  end

  it "keeps CSRF protection on all website mutations" do
    login
    save_draft(summary: "Protected draft")
    original = setting.reload.attributes.slice("draft", "published", "lock_version")
    protection = ActionController::Base.allow_forgery_protection
    begin
      ActionController::Base.allow_forgery_protection = true
      all_mutations { expect(response).to have_http_status(:unprocessable_entity) }
      expect(setting.reload.attributes.slice(*original.keys)).to eq(original)
    ensure
      ActionController::Base.allow_forgery_protection = protection
    end
  end
end
