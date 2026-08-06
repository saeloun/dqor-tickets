require "rails_helper"

RSpec.describe "Home", type: :request do
  it "renders the conference home with a tickets call to action" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Deccan Queen on Rails")
    expect(response.body).to include("Get your pass")
    expect(response.body).to include(tickets_store_path)
  end

  it "links the branded favicons, not the generic Rails placeholder" do
    get root_path

    expect(response.body).to include('href="/favicon.ico"')
    expect(response.body).to include('href="/dqor/favicon-32x32.png"')
    expect(response.body).to include('sizes="180x180" href="/dqor/apple-touch-icon.png"')
    expect(response.body).not_to include("/icon.svg")
  end

  it "serves the ticket storefront at /tickets" do
    get tickets_store_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Choose your conference pass")
  end
end
