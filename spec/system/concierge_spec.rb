require "rails_helper"

RSpec.describe "Concierge", type: :system do
  it "answers a question submitted in the browser" do
    allow(Ai::Concierge).to receive(:answer).and_return("The conference is October 8 to 11, 2026 in Pune.")

    visit concierge_path
    fill_in "Your question", with: "When and where is it?"
    click_button "Ask"

    expect(page).to have_content("October 8 to 11, 2026 in Pune")
  end

  it "uses fresh public pricing in the browser through an intercepted Anthropic request" do
    ticket_type = create(:ticket_type, slug: "rails-girls-pune", price_paise: 25_000)
    allow(ENV).to receive(:[]).and_call_original
    %w[OPENAI_API_KEY ANTHROPIC_API_KEY KIMI_API_KEY MOONSHOT_API_KEY CONCIERGE_MODEL].each do |key|
      allow(ENV).to receive(:[]).with(key).and_return(key == "ANTHROPIC_API_KEY" ? "synthetic-concierge-key" : nil)
    end
    prompts = []
    provider_request = stub_request(:post, "https://api.anthropic.com/v1/messages").to_return do |request|
      payload = JSON.parse(request.body)
      prompts << payload.fetch("system")
      price = prompts.last[/a (₹[\d,.]+) Rails Girls Pune ticket/, 1]
      answer = price ? "Rails Girls Pune costs #{price} including GST." : "See the tickets page for current Rails Girls pricing."
      { status: 200, body: JSON.generate(content: [ { type: "text", text: answer } ]) }
    end

    visit concierge_path
    fill_in "Your question", with: "What does Rails Girls Pune cost?"
    click_button "Ask"
    expect(page).to have_content("Rails Girls Pune costs ₹250 including GST.")
    expect(page).not_to have_content("₹350")
    page.save_screenshot(Rails.root.join("tmp/capybara/concierge-canonical-price.png"))

    ticket_type.update!(price_paise: 27_500)
    click_button "Ask"
    expect(page).to have_content("Rails Girls Pune costs ₹275 including GST.")
    expect(page).not_to have_content("₹250")

    ticket_type.update!(hidden: true)
    click_button "Ask"
    expect(page).to have_content("See the tickets page for current Rails Girls pricing.")
    expect(page).not_to have_content(/₹(?:275|250|350)/)
    expect(prompts.last).not_to include("₹")
    expect(provider_request).to have_been_requested.times(3)
  end
end
