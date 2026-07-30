require "rails_helper"

RSpec.describe "App tab bar", type: :request do
  it "renders the standalone app tab bar in the layout for web" do
    get account_sign_in_path

    expect(response.body).to include("app-tabbar")
    expect(response.body).to include(my_tickets_path)
  end

  it "omits the tab bar inside the native app" do
    get account_sign_in_path, headers: { "User-Agent" => "DQOR Hotwire Native" }

    expect(response.body).not_to include("app-tabbar")
  end
end
