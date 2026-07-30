require "rails_helper"

RSpec.describe "PWA", type: :request do
  it "serves an installable web app manifest" do
    get "/manifest.json"

    expect(response).to have_http_status(:ok)
    manifest = JSON.parse(response.body)
    expect(manifest["display"]).to eq("standalone")
    expect(manifest["start_url"]).to eq("/")
    expect(manifest["icons"]).to be_present
    expect(manifest["theme_color"]).to eq("#981B34")
  end

  it "serves the service worker as JavaScript with push handlers" do
    get "/service-worker.js"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to include("javascript")
    expect(response.body).to include("addEventListener")
    expect(response.body).to include("push")
  end

  it "sets the iOS installed-app title and status bar style" do
    get account_sign_in_path

    expect(response.body).to include('name="apple-mobile-web-app-title"')
    expect(response.body).to include('name="apple-mobile-web-app-status-bar-style"')
  end
end
