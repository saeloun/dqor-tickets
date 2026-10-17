require "rails_helper"

RSpec.describe Ai::Concierge, "public ticket pricing" do
  def use_provider(key)
    allow(ENV).to receive(:[]).and_call_original
    %w[OPENAI_API_KEY ANTHROPIC_API_KEY KIMI_API_KEY MOONSHOT_API_KEY CONCIERGE_MODEL].each do |name|
      allow(ENV).to receive(:[]).with(name).and_return(name == key ? "synthetic-concierge-key" : nil)
    end
  end

  def capture_prompts(endpoint, messages: false)
    prompts = []
    stub_request(:post, endpoint).to_return do |request|
      payload = JSON.parse(request.body)
      prompts << (messages ? payload.fetch("system") : payload.fetch("messages").find { |message| message.fetch("role") == "system" }.fetch("content"))
      body = messages ? { content: [ { type: "text", text: "See the tickets page." } ] } : { choices: [ { message: { content: "See the tickets page." } } ] }
      { status: 200, body: JSON.generate(body), headers: { "content-type" => "application/json" } }
    end
    prompts
  end

  [
    [ "OPENAI_API_KEY", "https://api.openai.com/v1/chat/completions", false ],
    [ "ANTHROPIC_API_KEY", "https://api.anthropic.com/v1/messages", true ],
    [ "KIMI_API_KEY", "https://api.moonshot.ai/v1/chat/completions", false ],
    [ "MOONSHOT_API_KEY", "https://api.moonshot.cn/v1/chat/completions", false ]
  ].each do |key, endpoint, messages|
    context "with #{key}" do
      before { use_provider(key) }
      let(:prompts) { capture_prompts(endpoint, messages:) }

      def ask_for_price
        prompts
        expect(described_class.answer("How much is Rails Girls Pune?")).to eq("See the tickets page.")
        prompts.last
      end

      it "sends the canonical public legacy ₹250 ticket price" do
        create(:ticket_type, name: "Rails Girls Pune", slug: "rails-girls-pune", price_paise: 25_000, hidden: false)

        expect(ask_for_price).to include("a ₹250 Rails Girls Pune ticket for October 10")
        expect(prompts.last).not_to include("₹350")
      end

      it "reads a changed price on the next answer in the same process" do
        ticket_type = create(:ticket_type, slug: "rails-girls-pune", price_paise: 25_000)
        expect(ask_for_price).to include("₹250")
        ticket_type.update!(price_paise: 27_500)

        expect(ask_for_price).to include("₹275")
        expect(prompts.last).not_to include("₹250", "₹350")
        expect(prompts.length).to eq(2)
      end

      it "preserves paise in the current ticket price" do
        create(:ticket_type, slug: "rails-girls-pune", price_paise: 125_050)

        expect(ask_for_price).to include("a ₹1,250.50 Rails Girls Pune ticket for October 10")
      end

      it "directs pricing to the tickets page when the public ticket is missing" do
        expect(ask_for_price).to include("Rails Girls Pune ticket for October 10", "tickets page for current pricing")
        expect(prompts.last).not_to include("₹")
      end

      it "does not quote hidden legacy inventory" do
        create(:ticket_type, name: "Private workshop", slug: "rails-girls-pune", price_paise: 98_765, hidden: true)

        expect(ask_for_price).to include("tickets page for current pricing")
        expect(prompts.last).not_to include("₹", "Private workshop")
      end

      it "does not quote event-owned inventory" do
        organization = Organization.create!(name: "Private organizer", slug: "concierge-private")
        event = organization.events.create!(title: "Private workshop", slug: "private-workshop")
        create(:ticket_type, name: "Private tenant ticket", slug: "rails-girls-pune", event_id: event.id, price_paise: 98_765, hidden: true, active: false)

        queries = []
        subscriber = ->(*arguments) do
          sql = arguments.last.fetch(:sql)
          queries << sql if sql.match?(/\ASELECT\b/) && sql.include?('"ticket_types"')
        end
        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          expect(ask_for_price).to include("tickets page for current pricing")
        end

        expect(queries).not_to be_empty
        expect(queries).to all(match(/"ticket_types"\."event_id"\s+IS NULL/))
        expect(prompts.last).not_to include("₹", "Private tenant ticket", "Private workshop", "Private organizer")
      end
    end
  end

  it "does not substitute a different public ticket's price" do
    use_provider("OPENAI_API_KEY")
    create(:ticket_type, name: "Rails Girls Pune", slug: "another-workshop", price_paise: 25_000)
    prompts = capture_prompts("https://api.openai.com/v1/chat/completions")

    expect(described_class.answer("Rails Girls price?")).to eq("See the tickets page.")
    expect(prompts.fetch(0)).to include("tickets page for current pricing")
    expect(prompts.fetch(0)).not_to include("₹")
  end

  it "keeps the existing fallback when the price lookup fails" do
    use_provider("OPENAI_API_KEY")
    allow(TicketType).to receive(:legacy).and_raise(ActiveRecord::ConnectionNotEstablished, "synthetic lookup failure")

    expect(described_class.answer("Rails Girls price?")).to eq(described_class.fallback)
    expect(a_request(:post, "https://api.openai.com/v1/chat/completions")).not_to have_been_made
  end

  it "keeps the existing fallback when the provider rejects the request" do
    use_provider("OPENAI_API_KEY")
    create(:ticket_type, slug: "rails-girls-pune", price_paise: 25_000)
    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(status: 503)

    expect(described_class.answer("Rails Girls price?")).to eq(described_class.fallback)
  end
end
