require "rails_helper"

RSpec.describe "Conference chat launch", type: :system do
  [ [ :community_path, 390, 844 ], [ :account_root_path, 1400, 1000 ] ].each do |route, width, height|
    it "opens chat from #{route} in a separate window and retains the original account session" do
      user = User.create!(email: "synthetic-chat-launch@example.com", name: "Synthetic chat attendee")
      User.create!(email: "synthetic-chat-neighbor@example.com", name: "Synthetic chat neighbor", discoverable: true)
      token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
      visit account_magic_path(token: token)
      origin = URI.parse(page.current_url)
      destination = "#{origin.scheme}://#{origin.host}:#{origin.port}/offline.html"
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("CAMPFIRE_JOIN_URL", "https://chat.deccanqueenonrails.com").and_return(destination)
      page.driver.browser.resize(width: width, height: height)
      visit public_send(route)
      expect(page).to have_content("Opens in a new tab")
      link = find_link("Open conference chat")
      expect(link[:href]).to eq(destination)
      expect(link[:target]).to eq("_blank")
      expect(link[:rel].split).to include("noopener")
      expect(page).to have_no_css("iframe")
      if route == :community_path
        expect(page).to have_content("Synthetic chat neighbor")
        expect(page).to have_css(".account-section", style: { "opacity" => "1" })
      else
        expect(page).to have_content(user.email)
        expect(page).to have_css(".account-header", style: { "opacity" => "1" })
      end
      page.save_screenshot(Rails.root.join("tmp/capybara/chat-launch-#{width}.png"))
      original = current_window
      new_tab = nil
      expect do
        new_tab = window_opened_by { click_on "Open conference chat" }
      end.not_to change(ChatLoginGrant, :count)
      expect(new_tab).not_to eq(original)
      within_window(new_tab) do
        expect(page).to have_current_path("/offline.html")
        expect(page).to have_content("You're offline")
        expect(page.evaluate_script("window.opener === null")).to be(true)
      end
      new_tab.close
      new_tab = nil
      expect(current_window).to eq(original)
      expect(page).to have_current_path(public_send(route))
      page.refresh
      expect(page).to have_css(route == :community_path ? ".account-section" : ".account-header", style: { "opacity" => "1" })
      expect(page).to have_link("Open conference chat", href: destination)
      visit account_root_path
      expect(page).to have_content(user.email)
      expect(page).to have_css(".account-header", style: { "opacity" => "1" })
      click_on "Sign out"
      visit account_root_path
      expect(page).to have_current_path(account_sign_in_path)
      expect(page).to have_no_content(user.email)
    ensure
      new_tab&.close
    end
  end
end
