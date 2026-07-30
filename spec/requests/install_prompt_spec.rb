require "rails_helper"

RSpec.describe "PWA install prompt", type: :request do
  it "includes the install prompt in the layout for web browsers" do
    get account_sign_in_path

    expect(response.body).to include("install-prompt")
    expect(response.body).to include('data-controller="install"')
  end

  it "omits the install prompt inside the native app" do
    get account_sign_in_path, headers: { "User-Agent" => "DQOR iOS Hotwire Native" }

    expect(response.body).not_to include("install-prompt")
  end
end
