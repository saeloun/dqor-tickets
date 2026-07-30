require "rails_helper"

RSpec.describe "FAQ", type: :request do
  it "shows published FAQs and hides drafts" do
    Faq.create!(question: "Do I need a password?", answer: "No, email sign-in works.", published: true)
    Faq.create!(question: "Secret draft question", published: false)

    get faq_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Do I need a password?")
    expect(response.body).not_to include("Secret draft question")
  end

  it "renders an empty state when there are none" do
    get faq_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("coming soon")
  end
end
