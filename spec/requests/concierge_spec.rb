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

  it "sends the public canonical price through the real concierge HTTP integration" do
    create(:ticket_type, slug: "rails-girls-pune", price_paise: 25_000)
    allow(ENV).to receive(:[]).and_call_original
    %w[OPENAI_API_KEY ANTHROPIC_API_KEY KIMI_API_KEY MOONSHOT_API_KEY CONCIERGE_MODEL].each do |key|
      allow(ENV).to receive(:[]).with(key).and_return(key == "OPENAI_API_KEY" ? "synthetic-concierge-key" : nil)
    end
    payload = nil
    provider_request = stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return do |request|
      payload = JSON.parse(request.body)
      prompt = payload.fetch("messages").first.fetch("content")
      price = prompt[/a (₹[\d,.]+) Rails Girls Pune ticket/, 1]
      { status: 200, body: JSON.generate(choices: [ { message: { content: "Rails Girls Pune costs #{price} including GST. See the tickets page." } } ]) }
    end

    post concierge_path, params: { question: "What does Rails Girls Pune cost?" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rails Girls Pune costs ₹250 including GST.")
    expect(response.body).not_to include("₹350")
    expect(payload.fetch("messages").first.fetch("content")).to include("a ₹250 Rails Girls Pune ticket for October 10")
    expect(payload.fetch("messages").last).to eq("role" => "user", "content" => "What does Rails Girls Pune cost?")
    expect(provider_request).to have_been_requested.once
  end
end
