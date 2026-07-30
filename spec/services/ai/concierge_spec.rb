require "rails_helper"

RSpec.describe Ai::Concierge do
  PROVIDER_KEYS = %w[OPENAI_API_KEY ANTHROPIC_API_KEY KIMI_API_KEY MOONSHOT_API_KEY CONCIERGE_MODEL].freeze

  def only_key(name, value)
    allow(ENV).to receive(:[]).and_call_original
    PROVIDER_KEYS.each { |key| allow(ENV).to receive(:[]).with(key).and_return(key == name ? value : nil) }
  end

  def http_ok(body)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(body)
    response
  end

  it "falls back when no provider key is set" do
    only_key("NONE", nil)

    expect(Ai::Concierge.answer("When is it?")).to match(/deccanqueenonrails/i)
  end

  it "falls back for a blank question" do
    expect(Ai::Concierge.answer("  ")).to eq(Ai::Concierge.fallback)
  end

  it "uses an OpenAI-compatible key and parses chat completions" do
    only_key("OPENAI_API_KEY", "test")
    allow_any_instance_of(Net::HTTP).to receive(:request)
      .and_return(http_ok(JSON.generate(choices: [ { message: { content: "October 8 to 11, 2026." } } ])))

    expect(Ai::Concierge.answer("When?")).to eq("October 8 to 11, 2026.")
  end

  it "uses an Anthropic key and parses the messages format" do
    only_key("ANTHROPIC_API_KEY", "test")
    allow_any_instance_of(Net::HTTP).to receive(:request)
      .and_return(http_ok(JSON.generate(content: [ { type: "text", text: "Hyatt Regency, Pune." } ])))

    expect(Ai::Concierge.answer("Where?")).to eq("Hyatt Regency, Pune.")
  end

  it "uses a Kimi key via the chat-completions shape" do
    only_key("KIMI_API_KEY", "test")
    allow_any_instance_of(Net::HTTP).to receive(:request)
      .and_return(http_ok(JSON.generate(choices: [ { message: { content: "Buy on the tickets page." } } ])))

    expect(Ai::Concierge.answer("Tickets?")).to eq("Buy on the tickets page.")
  end

  it "falls back when the request errors" do
    only_key("OPENAI_API_KEY", "test")
    allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Timeout::Error)

    expect(Ai::Concierge.answer("Anything?")).to eq(Ai::Concierge.fallback)
  end
end
