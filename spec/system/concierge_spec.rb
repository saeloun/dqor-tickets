require "rails_helper"

RSpec.describe "Concierge", type: :system do
  it "answers a question submitted in the browser" do
    allow(Ai::Concierge).to receive(:answer).and_return("The conference is October 8 to 11, 2026 in Pune.")

    visit concierge_path
    fill_in "Your question", with: "When and where is it?"
    click_button "Ask"

    expect(page).to have_content("October 8 to 11, 2026 in Pune")
  end
end
