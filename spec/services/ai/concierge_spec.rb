require "rails_helper"

RSpec.describe Ai::Concierge do
  it "returns a fallback when no API key is configured" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)

    expect(described_class.answer("When is the conference?")).to match(/deccanqueenonrails/i)
  end

  it "returns a fallback for a blank question" do
    expect(described_class.answer("  ")).to eq(described_class.fallback)
  end

  it "calls the API and returns the model text when a key is set" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("test-key")

    ok = Net::HTTPOK.new("1.1", "200", "OK")
    allow(ok).to receive(:body).and_return(JSON.generate(content: [ { type: "text", text: "October 8 to 11, 2026 in Pune." } ]))
    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(ok)

    expect(described_class.answer("When and where?")).to eq("October 8 to 11, 2026 in Pune.")
  end

  it "returns a fallback when the API errors" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("test-key")
    allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Timeout::Error)

    expect(described_class.answer("Anything?")).to eq(described_class.fallback)
  end
end
