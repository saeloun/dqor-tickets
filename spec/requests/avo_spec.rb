require "rails_helper"

RSpec.describe "Avo admin", type: :request do
  it "redirects unauthenticated visitors to the existing sign-in" do
    get "/avo"

    expect(response).to redirect_to("/session/new")
  end

  it "allows an authenticated admin to load resources and the dashboard" do
    sign_in_admin

    get "/avo/resources/orders"
    expect(response).to have_http_status(:ok)

    get "/avo/dashboard"
    expect(response).to have_http_status(:ok)
  end
end
