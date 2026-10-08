require "rails_helper"

RSpec.describe "Printable conference badges", type: :system do
  let(:admin) { create(:admin_user, role: :admin, password: "password123") }
  let(:type) { create(:ticket_type, slug: "conference-pass-regular") }
  let(:ticket) { create(:ticket, ticket_type: type, order: create(:order, :paid), attendee_name: "Synthetic Badge Ada", attendee_email: "private-badge@example.com") }

  def open_badges(operator = admin)
    visit checkin_path
    fill_in "email", with: operator.email
    fill_in "password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path(checkin_path)
    click_link "Print conference badges"
    expect(page).to have_content("Conference lanyard badges")
  end

  it "lets an admin review a sample then explicitly select and prepare private printable badges" do
    ticket
    open_badges
    click_link "Review sample HTML"
    expect(page).to have_css(".conference-badge--sample", count: 4)
    expect(page).to have_content("SAMPLE / REHEARSAL")
    expect(page).to have_content("NOT ADMISSION")
    click_link "Back to badge selection"
    check "Synthetic Badge Ada · Pass #{ticket.id}"
    fill_in "Company for pass #{ticket.id} (optional)", with: "Synthetic Ruby team"
    check "I reviewed the selected passes and duplicate warnings"
    click_button "Prepare printable HTML"

    expect(page).to have_css(".conference-badge", count: 1)
    expect(page).to have_content(ticket.attendee_name)
    expect(page).to have_content("Synthetic Ruby team")
    expect(page).to have_css(".badge-qr svg")
    expect(page).not_to have_content(ticket.attendee_email, exact: false)
    expect(page.html).not_to include(ticket.secret, ticket.claim_token)
    expect(ticket.reload.checked_in_at).to eq({})
    expect(CheckinAudit.count).to eq(0)
    expect(EventSlotRedemption.count).to eq(0)
    page.save_screenshot(Rails.root.join("tmp/capybara/conference-badge-selected.png"))
  end

  it "keeps the native selection form usable at 320 pixels with missing names and duplicate warnings" do
    ticket
    create(:ticket, order: ticket.order, ticket_type: type, attendee_name: ticket.attendee_name.upcase)
    missing = create(:ticket, order: ticket.order, ticket_type: type, attendee_name: nil)
    page.driver.browser.resize(width: 320, height: 812)
    open_badges
    expect(page).to have_content("Duplicate attendee identity — review")
    expect(page).to have_field("badge_ticket_#{missing.id}", disabled: true)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    expect(ticket.reload.checked_in_at).to eq({})
  end

  it "revalidates a pass canceled after the browser selected it" do
    ticket
    open_badges
    check "Synthetic Badge Ada · Pass #{ticket.id}"
    check "I reviewed the selected passes and duplicate warnings"
    ticket.update!(canceled_at: Time.current)
    click_button "Prepare printable HTML"
    expect(page).to have_content("no longer a confirmed conference pass")
    expect(page).to have_no_css(".badge-qr")
    expect(CheckinAudit.count).to eq(0)
  end

  [ :admin, :desk ].each do |role|
    it "lets existing #{role} staff navigate, review a sample and submit a confirmed native PDF form" do
      ticket
      operator = create(:admin_user, role:, password: "password123")
      open_badges(operator)
      expect(page).to have_link("Registration desk", href: checkin_path)
      expect(page).to have_no_link("Admin") if role == :desk
      click_link "Review sample HTML"
      expect(page).to have_css(".conference-badge--sample", count: 4)
      expect(page).to have_content("NOT ADMISSION")
      click_link "Back to badge selection"
      check "Synthetic Badge Ada · Pass #{ticket.id}"
      check "I reviewed the selected passes and duplicate warnings"
      click_button "Prepare PDF"
      expect(page).to have_current_path(print_conference_badges_path(format: :pdf))
      exchange = page.driver.browser.network.traffic.reverse.find { |item| item.url&.end_with?(print_conference_badges_path(format: :pdf)) && item.response }
      expect(exchange).not_to be_nil
      expect(exchange.response.status).to eq(200)
      expect(exchange.response.content_type).to eq("application/pdf")
      expect(ticket.reload.checked_in_at).to eq({})
      expect(operator.reload.role).to eq(role.to_s)
      expect(CheckinAudit.count).to eq(0)
      expect(EventSlotRedemption.count).to eq(0)
    end
  end

  it "denies a signed-in tenant organizer access to staff badge selection" do
    user = User.create!(email: "synthetic-badge-tenant@example.test")
    organization = Organization.create!(name: "Other organizer", slug: "badge-browser-other")
    Membership.create!(organization:, user:, role: :owner)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token:)
    visit conference_badges_path
    expect(page).to have_current_path(new_session_path)
    expect(page).to have_no_content("Conference lanyard badges")
    expect(AdminUser.count).to eq(0)
    expect(CheckinAudit.count).to eq(0)
  end

  it "requires renewed staff authentication if a desk session is revoked before print confirmation" do
    ticket
    operator = create(:admin_user, role: :desk, password: "password123")
    open_badges(operator)
    check "Synthetic Badge Ada · Pass #{ticket.id}"
    check "I reviewed the selected passes and duplicate warnings"
    operator.sessions.destroy_all
    click_button "Prepare printable HTML"
    expect(page).to have_current_path(new_session_path)
    expect(page).to have_no_css(".badge-qr")
    expect(ticket.reload.checked_in_at).to eq({})
    expect(CheckinAudit.count).to eq(0)
  end
end
