require "rails_helper"

RSpec.describe "Account", type: :system do
  it "signs in with a magic link and shows the account" do
    user = User.create!(email: "grace@example.com", name: "Grace Hopper")
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)

    visit account_magic_path(token: token)

    expect(page).to have_content("Grace Hopper")
    expect(page).to have_content("grace@example.com")
    expect(page).to have_content("Your tickets")
    expect(page).to have_content("Connect with me")
    expect(page).to have_link("Scan to connect")
    expect(page).to have_css(".connect-card__qr svg")
  end

  it "shows the sign-in form" do
    visit account_sign_in_path

    expect(page).to have_content("Sign in")
    expect(page).to have_field("Email")
  end

  it "shows the entry-pass QR on the dashboard for a ticket holder" do
    order = create(:order, :paid, email: "grace@example.com")
    type = create(:ticket_type, name: "Rails Girls Pune Pass", event_starts_on: "2026-10-10", event_ends_on: "2026-10-10")
    create(:ticket, order:, ticket_type: type)
    user = User.create!(email: "grace@example.com")
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)

    visit account_magic_path(token: token)
    first("summary", text: "Show entry pass").click

    expect(page).to have_css(".entry-pass__qr svg", visible: true)
    expect(page).to have_css(".entry-pass__date", text: "October 10, 2026 · Pune", visible: true)
    expect(page).not_to have_css(".entry-pass__date", text: "October 8–11")
  end
end
