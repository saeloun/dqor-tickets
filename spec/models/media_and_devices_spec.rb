require "rails_helper"

RSpec.describe "Media, video and devices" do
  let(:event) { create(:event) }
  let(:user) { create(:user) }

  it "records an uploaded media item pending moderation" do
    item = event.media_items.create!(user:, kind: "image", source: "upload")

    expect(item.moderation_state).to eq("pending")
    expect(event.media_items.approved).to be_empty

    item.update!(moderation_state: "approved")
    expect(event.media_items.approved).to include(item)
  end

  it "ingests external instagram media with attribution and consent" do
    item = event.media_items.create!(kind: "image", source: "instagram", external_url: "https://insta/abc", external_ref: "abc", attribution: "@someone", consent_given: true)

    expect(item.source).to eq("instagram")
    expect(item).to be_consent_given
  end

  it "configures a gallery curation source" do
    source = event.gallery_sources.create!(provider: "instagram", query: "#rubyconfindia")

    expect(source).to be_active
    expect(source).to be_instagram
    expect(event.gallery_sources).to include(source)
  end

  it "tracks a talk video asset through to published" do
    session = event.program_sessions.create!(title: "Talk")
    asset = session.video_assets.create!(status: "uploaded", youtube_id: "yt123", title: "Talk")

    expect(asset).to be_uploaded
    asset.update!(status: "published", published_at: Time.current)
    expect(asset).to be_published
    expect(session.video_assets).to include(asset)
  end

  it "registers a push device uniquely per platform and token" do
    user.push_devices.create!(platform: "ios", token: "tok")

    expect(user.push_devices.new(platform: "ios", token: "tok")).not_to be_valid
    expect(user.push_devices.new(platform: "android", token: "tok")).to be_valid
  end
end
