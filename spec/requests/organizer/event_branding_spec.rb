require "rails_helper"

RSpec.describe "Organizer event branding", type: :request do
  let(:setting) { EventBrandingSetting.current }
  let(:operator) { create(:admin_user) }

  def draft_params(**overrides)
    setting.reload.draft.except("version", "assets").merge("lock_version" => setting.lock_version).merge(overrides.stringify_keys)
  end

  def upload_image
    Rack::Test::UploadedFile.new(Rails.root.join("public/dqor/favicon-32x32.png"), "image/png")
  end

  def save_draft(**overrides)
    patch organizer_branding_path, params: { branding: draft_params(**overrides) }
  end

  it "requires a staff session for reads, writes and private images" do
    get organizer_branding_path
    expect(response).to redirect_to(new_session_path)
    get preview_organizer_branding_path
    expect(response).to redirect_to(new_session_path)
    get asset_organizer_branding_path(id: 1)
    expect(response).to redirect_to(new_session_path)
    patch organizer_branding_path, params: { branding: { theme: "marathon" } }
    expect(response).to redirect_to(new_session_path)
    post publish_organizer_branding_path
    expect(response).to redirect_to(new_session_path)
    post rollback_organizer_branding_path
    expect(response).to redirect_to(new_session_path)
    expect(EventBrandingSetting.count).to eq(0)
  end

  it "denies desk staff across every endpoint without creating settings" do
    sign_in_admin(create(:admin_user, role: :desk))
    [ organizer_branding_path, preview_organizer_branding_path, asset_organizer_branding_path(id: 1) ].each do |path|
      get path
      expect(response).to have_http_status(:forbidden)
    end
    patch organizer_branding_path, params: { branding: { theme: "marathon" } }
    expect(response).to have_http_status(:forbidden)
    [ publish_organizer_branding_path, rollback_organizer_branding_path ].each do |path|
      post path, params: { confirmed: "1", lock_version: 0 }
      expect(response).to have_http_status(:forbidden)
    end
    expect(EventBrandingSetting.count).to eq(0)
  end

  it "does not treat an attendee account as an organizer" do
    user = User.create!(email: "branding-attendee@example.test")
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
    get organizer_branding_path
    expect(response).to redirect_to(new_session_path)
  end

  it "saves the singleton draft and previews the real event identity privately" do
    sign_in_admin(operator)
    save_draft(theme: "campus", accent: "#123456", sections: %w[visit about programme])
    expect(response).to redirect_to(organizer_branding_path)
    expect(setting.reload.draft).to include("theme" => "campus", "accent" => "#123456", "sections" => %w[visit about programme])
    expect(setting.updated_by).to eq(operator)
    expect(setting.published).to be_nil
    get preview_organizer_branding_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Deccan Queen on Rails", Conference::VENUE, Conference::DATE_RANGE_LABEL)
    expect(response.body).to include('data-theme="campus"', "--dq-accent:#123456")
    expect(response.body.index('id="visit"')).to be < response.body.index('id="about"')
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(EventBrandingSetting.count).to eq(1)
  end

  it "rejects stale writes rather than losing another admin's changes" do
    sign_in_admin(operator)
    stale = draft_params(accent: "#111111")
    save_draft(accent: "#222222")
    patch organizer_branding_path, params: { branding: stale }
    expect(response).to have_http_status(:conflict)
    expect(response.body).to include("changed in another session")
    expect(setting.reload.draft.fetch("accent")).to eq("#222222")
  end

  it "rejects arbitrary fields, invalid colors, duplicate sections and missing revisions" do
    sign_in_admin(operator)
    [ { css: "body{display:none}" }, { event_id: 2 }, { accent: "red; background:url(https://example.com)" }, { sections: %w[about about visit] }, { lock_version: "" } ].each do |changes|
      original = setting.reload.draft
      save_draft(**changes)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(setting.reload.draft).to eq(original)
    end
  end

  it "stores decoded raster images privately and requires admin authentication for their bytes" do
    sign_in_admin(operator)
    save_draft(logo: upload_image, favicon: upload_image)
    expect(response).to redirect_to(organizer_branding_path)
    image = setting.reload.assets.find(setting.draft.fetch("assets").fetch("logo"))
    expect(image.content_type).to eq("image/webp")
    expect(image.image_data.byteslice(8, 4)).to eq("WEBP")
    get asset_organizer_branding_path(id: image.id)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/webp")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    delete session_path
    get asset_organizer_branding_path(id: image.id)
    expect(response).to redirect_to(new_session_path)
  end

  it "rejects SVG and invalid raster bytes without partial draft or image writes" do
    sign_in_admin(operator)
    Tempfile.create([ "unsafe", ".svg" ]) do |file|
      file.write('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')
      file.flush
      save_draft(logo: upload_image, cover: Rack::Test::UploadedFile.new(file.path, "image/png"))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(setting.reload.draft.fetch("assets")).to be_empty
      expect(setting.assets.count).to eq(0)
    end
  end

  it "rolls back uploaded images when configuration validation fails" do
    sign_in_admin(operator)
    save_draft(logo: upload_image, theme: "unknown")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(setting.reload.assets.count).to eq(0)
  end

  it "publishes only the saved draft with confirmation and a current revision" do
    sign_in_admin(operator)
    save_draft(accent: "#123456")
    revision = setting.reload.lock_version
    post publish_organizer_branding_path, params: { lock_version: revision }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(setting.reload.published).to be_nil
    post publish_organizer_branding_path, params: { lock_version: revision, confirmed: "1", accent: "#000000" }
    expect(response).to redirect_to(organizer_branding_path)
    expect(setting.reload.published.fetch("accent")).to eq("#123456")
    expect(setting.published_by).to eq(operator)
    expect(setting.published_at).to be_present
    expect(setting.configuration_for_public_rendering).to be_nil
    save_draft(accent: "#654321")
    expect(setting.reload.published.fetch("accent")).to eq("#123456")
    get preview_organizer_branding_path(snapshot: "published")
    expect(response.body).to include("--dq-accent:#123456")
    post publish_organizer_branding_path, params: { lock_version: revision, confirmed: "1" }
    expect(response).to have_http_status(:conflict)
  end

  it "restores the previous publication without overwriting the draft or deleting referenced images" do
    sign_in_admin(operator)
    save_draft(logo: upload_image, accent: "#112233")
    first_asset = setting.reload.draft.fetch("assets").fetch("logo")
    post publish_organizer_branding_path, params: { lock_version: setting.reload.lock_version, confirmed: "1" }
    save_draft(logo: upload_image, accent: "#445566")
    post publish_organizer_branding_path, params: { lock_version: setting.reload.lock_version, confirmed: "1" }
    saved_draft = setting.reload.draft.deep_dup
    post rollback_organizer_branding_path, params: { lock_version: setting.lock_version, confirmed: "1" }
    expect(response).to redirect_to(organizer_branding_path)
    expect(setting.reload.published.fetch("accent")).to eq("#112233")
    expect(setting.draft).to eq(saved_draft)
    expect(setting.assets.exists?(first_asset)).to be(true)
    expect(setting.configuration_for_public_rendering).to be_nil
  end

  it "rejects rollback without a prior publication or confirmation" do
    sign_in_admin(operator)
    post rollback_organizer_branding_path, params: { lock_version: setting.lock_version, confirmed: "1" }
    expect(response).to have_http_status(:unprocessable_entity)
    post rollback_organizer_branding_path, params: { lock_version: setting.lock_version }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "removes unreferenced draft images without deleting a published image" do
    sign_in_admin(operator)
    save_draft(logo: upload_image)
    image_id = setting.reload.draft.fetch("assets").fetch("logo")
    post publish_organizer_branding_path, params: { lock_version: setting.lock_version, confirmed: "1" }
    save_draft(remove_assets: [ "logo" ])
    expect(setting.reload.draft.fetch("assets")).to be_empty
    expect(setting.assets.exists?(image_id)).to be(true)
    save_draft(cover: upload_image)
    draft_image_id = setting.reload.draft.fetch("assets").fetch("cover")
    save_draft(remove_assets: [ "cover" ])
    expect(setting.assets.exists?(draft_image_id)).to be(false)
  end

  it "keeps CSRF protection on mutations" do
    sign_in_admin(operator)
    original = setting.draft
    begin
      ActionController::Base.allow_forgery_protection = true
      save_draft(accent: "#333333")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(setting.reload.draft).to eq(original)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end
end
