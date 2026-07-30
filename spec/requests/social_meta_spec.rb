require "rails_helper"

RSpec.describe "Social share meta", type: :request do
  it "renders Open Graph and Twitter card tags in the layout" do
    get "/login"

    expect(response.body).to include('property="og:title"')
    expect(response.body).to include('property="og:image"')
    expect(response.body).to include('property="og:url"')
    expect(response.body).to include('name="twitter:card"')
    expect(response.body).to include('<meta name="description"')
  end
end
