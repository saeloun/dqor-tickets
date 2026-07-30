require "rails_helper"

RSpec.describe "Hotwire Native support", type: :request do
  describe "GET /hotwire-native/path-configuration" do
    it "returns JSON navigation rules for the native apps" do
      get "/hotwire-native/path-configuration"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["rules"]).to be_present
      expect(body["rules"].last["patterns"]).to include(".*")
    end
  end

  describe "web chrome" do
    it "renders the site header and footer for a normal browser" do
      get "/login"

      expect(response.body).to include("site-header")
      expect(response.body).to include("site-footer")
    end

    it "omits web chrome and marks the body when inside a native app" do
      get "/login", headers: { "User-Agent" => "DQOR/1.0 iOS Hotwire Native" }

      expect(response.body).not_to include("site-header")
      expect(response.body).not_to include("site-footer")
      expect(response.body).to include("hotwire-native")
    end
  end
end
