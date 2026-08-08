require "rails_helper"

RSpec.describe "Account connection scanner", type: :request do
  def sign_in_as(user)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
  end

  it "requires sign-in" do
    get account_connection_scan_path

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "renders the attendee scanner" do
    sign_in_as(User.create!(email: "scanner@example.com"))

    get account_connection_scan_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Scan to connect")
    expect(response.body).to include('data-controller="connect-scanner"')
  end
end
