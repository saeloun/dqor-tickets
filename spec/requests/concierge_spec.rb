require "rails_helper"

RSpec.describe "Concierge", type: :request do
  it "shows the concierge page" do
    get concierge_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ask about the conference")
  end

  it "answers a question" do
    allow(Ai::Concierge).to receive(:answer).with("When?").and_return("October 8 to 11, 2026.")

    post concierge_path, params: { question: "When?" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("October 8 to 11, 2026.")
  end
end
