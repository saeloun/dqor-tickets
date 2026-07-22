require "rails_helper"

RSpec.describe "Ticket access by email link", type: :system do
  let(:notice) { "If we have tickets for that address, we have sent a link" }

  def token_for(email)
    Rails.application.message_verifier(:ticket_access)
      .generate(email, purpose: TicketAccessController::TOKEN_PURPOSE, expires_in: TicketAccessController::TOKEN_EXPIRY)
  end

  it "is reachable from the storefront" do
    create(:ticket_type, name: "Early Bird", position: 1)

    visit root_path
    click_link "Email me my tickets"

    expect(page).to have_content("Get your tickets by email")
  end

  it "emails a link when the address has a paid order" do
    order = create(:order, :paid, email: "buyer@example.com")
    create(:ticket, order:)

    visit find_tickets_path
    fill_in "Email address", with: "buyer@example.com"

    expect do
      click_button "Email me my tickets"
      expect(page).to have_content(notice)
    end.to have_enqueued_mail(TicketAccessMailer, :link)
  end

  it "gives the same answer for an unknown address and sends nothing" do
    visit find_tickets_path
    fill_in "Email address", with: "nobody@example.com"

    expect do
      click_button "Email me my tickets"
      expect(page).to have_content(notice)
    end.not_to have_enqueued_mail(TicketAccessMailer, :link)
  end

  it "matches the address regardless of case" do
    order = create(:order, :paid, email: "buyer@example.com")
    create(:ticket, order:)

    visit find_tickets_path
    fill_in "Email address", with: "  BUYER@Example.com  "

    expect do
      click_button "Email me my tickets"
    end.to have_enqueued_mail(TicketAccessMailer, :link)
  end

  it "lists the paid orders behind a valid link" do
    order = create(:order, :paid, email: "buyer@example.com")
    ticket_type = create(:ticket_type, name: "Conference Pass")
    create(:ticket, order:, ticket_type:, attendee_name: "Grace Hopper")
    create(:ticket, order:, ticket_type:, attendee_name: "Ada Lovelace")
    create(:ticket, order:, ticket_type:, attendee_name: nil, attendee_email: nil)
    other = create(:order, :paid, email: "someone@example.com")
    create(:ticket, order: other)

    visit ticket_access_path(token_for("buyer@example.com"))

    expect(page).to have_content("Orders for buyer@example.com")
    expect(page).to have_link(order.code)
    expect(page).to have_content("3 tickets")
    expect(page).to have_content("2 assigned")
    expect(page).to have_no_content("assigneds")
    expect(page).to have_content("Grace Hopper")
    expect(page).to have_content("unassigned")
    expect(page).to have_no_link(other.code)
  end

  it "does not list pending or expired orders" do
    create(:order, email: "buyer@example.com")
    expired = create(:order, :paid, email: "buyer@example.com")
    expired.update!(status: :expired)

    visit ticket_access_path(token_for("buyer@example.com"))

    expect(page).to have_content("We could not find any paid orders")
  end

  it "rejects a forged token" do
    visit ticket_access_path("not-a-real-token")

    expect(page).to have_content("That link is invalid or has expired")
  end

  it "rejects a token older than a day" do
    create(:ticket, order: create(:order, :paid, email: "buyer@example.com"))
    token = token_for("buyer@example.com")

    travel 25.hours do
      visit ticket_access_path(token)
    end

    expect(page).to have_content("That link is invalid or has expired")
  end
end
