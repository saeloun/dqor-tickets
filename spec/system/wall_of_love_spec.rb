require "rails_helper"

RSpec.describe "Wall of Love journey", type: :system do
  def login(user)
    visit account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  it "submits, reviews, edits and withdraws a note with explicit public consent" do
    user = User.create!(email: "private-attendee@example.com")
    create(:order, :paid, email: user.email)
    admin = create(:admin_user, password: "password123")
    login(user)
    visit wall_of_love_path
    expect(page).to have_unchecked_field("I agree to publish this name, note and optional link on the public Wall of Love after review.")
    fill_in "Name to display publicly", with: "Ruby Friend"
    fill_in "Your thank-you note", with: "Thank you for bringing us together."
    fill_in "Original post or profile link (optional)", with: "https://example.com/public-post"
    check "I agree to publish this name, note and optional link on the public Wall of Love after review."
    click_button "Submit note for review"
    expect(page).to have_content("Your note is pending.")
    within("section", text: "From the community") do
      expect(page).not_to have_content("Ruby Friend")
    end

    visit new_session_path
    fill_in "Email address", with: admin.email
    fill_in "Password", with: "password123"
    click_button "Sign in"
    visit wall_love_review_path(WallLoveNote.last)
    expect(page).to have_content("Ruby Friend")
    click_button "Approve publication"
    expect(page).to have_content("Review decision saved.")
    visit wall_of_love_path
    within("section", text: "From the community") { expect(page).to have_content("Ruby Friend") }
    within("#your-note") do
      expect(page).to have_unchecked_field("I agree to publish this name, note and optional link on the public Wall of Love after review.")
      fill_in "Your thank-you note", with: "Thanks again for the conversations."
      check "I agree to publish this name, note and optional link on the public Wall of Love after review."
      click_button "Submit changes for review"
    end
    expect(page).to have_content("Your note is pending.")
    within("section", text: "From the community") { expect(page).not_to have_content("Ruby Friend") }
    click_button "Withdraw my note"
    expect(page).to have_content("Your note is withdrawn.")
    expect(page).not_to have_button("Withdraw my note")
  end

  it "offers accessible mobile navigation and an unchecked attendee form" do
    user = User.create!(email: "mobile-attendee@example.com")
    create(:order, :paid, email: user.email)
    login(user)
    page.driver.browser.resize(width: 390, height: 844)
    visit root_path
    find('button#nav-mobile-toggle[aria-label="Open menu"]').click
    expect(page).to have_css('button#nav-mobile-toggle[aria-expanded="true"]')
    expect(page).to have_css("#nav-mobile-menu.open")
    within("#nav-mobile-menu") { click_link "Wall of Love" }
    expect(page).to have_css("h1", text: "Wall of Love")
    expect(page).to have_link("Read original post", count: 4)
    click_link "Share a thank-you note"
    expect(page).to have_field("Name to display publicly", with: "")
    expect(page).to have_unchecked_field("I agree to publish this name, note and optional link on the public Wall of Love after review.")
    page.save_screenshot(Rails.root.join("tmp/wall-of-love-mobile.png"))
    page.driver.browser.resize(width: 320, height: 740)
    expect(page).to have_field("Your thank-you note")
    page.save_screenshot(Rails.root.join("tmp/wall-of-love-320.png"))
  end
end
