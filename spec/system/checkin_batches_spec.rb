require "rails_helper"

RSpec.describe "Staff batch check-in", type: :system do
  let(:operator) { create(:admin_user, role: :desk, password: "password123") }
  let(:order) { create(:order, :paid) }

  def open_desk
    visit checkin_path
    fill_in "email", with: operator.email
    fill_in "password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path(checkin_path)
  end

  it "opens only the Avo selection without recording attendance" do
    operator.update!(role: :admin)
    selected = create(:ticket, order:, attendee_name: "Selected Attendee")
    create(:ticket, order:, attendee_name: "Other Attendee")
    open_desk
    visit "/avo/resources/tickets"
    within("tr", text: "Selected Attendee") { check "Select item" }
    click_button "Actions"
    click_link "Check in selected tickets"
    expect(page).to have_current_path(checkin_path(ticket_ids: [ selected.id ]))
    expect(page).to have_content("Selected Attendee")
    expect(page).to have_no_content("Other Attendee")
    expect(selected.reload.checked_in_at).to be_empty
    expect(CheckinAudit.count).to eq(0)
  end

  it "requires confirmation, supports cancel/Escape, and returns an outcome per selected attendee" do
    first = create(:ticket, order:, attendee_name: "Test Grace")
    second = create(:ticket, order:, attendee_name: "Test Ada")
    second.check_in!(Date.new(2026, 10, 8))
    open_desk
    click_button "Select shown tickets"
    click_button "Review 2 selected tickets"
    expect(page).to have_css("dialog[open]", text: "2026-10-08")
    click_button "Cancel"
    expect(first.reload.checked_in_at).to be_empty
    click_button "Review 2 selected tickets"
    page.driver.browser.keyboard.type(:Escape)
    expect(page).to have_no_css("dialog[open]")
    expect(first.reload.checked_in_at).to be_empty
    click_button "Review 2 selected tickets"
    click_button "Confirm check-in"
    expect(page).to have_css("[aria-label='Batch results'] li", count: 2)
    expect(page).to have_css("[aria-label='Batch results']", text: "Test Grace: Checked in Test Grace")
    expect(page).to have_css("[aria-label='Batch results']", text: "Test Ada: Already checked in")
    expect(page).to have_button("Review 0 selected tickets", disabled: true)
    expect(CheckinAudit.where(outcome: "success", admin_user: operator).count).to eq(1)
  end

  it "uses only visible results on mobile, clearing selections when navigating/searching" do
    create_list(:ticket, 21, order:, attendee_name: "Test Attendee")
    page.driver.browser.resize(width: 375, height: 812)
    open_desk
    expect(page).to have_content("more matches exist")
    click_button "Select shown tickets"
    expect(page).to have_button("Review 20 selected tickets")
    fill_in "q", with: "nobody matches"
    click_button "Search"
    expect(page).to have_button("Review 0 selected tickets", disabled: true)
    expect(Ticket.pluck(:checked_in_at)).to all(eq({}))
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
  end

  it "reports a lost connection without success or a count increase and keeps retry selection" do
    ticket = create(:ticket, order:, attendee_name: "Test Offline")
    open_desk
    click_button "Select shown tickets"
    click_button "Review 1 selected ticket"
    page.execute_script("window.fetch = () => Promise.reject(new TypeError('offline'))")
    click_button "Confirm check-in"
    expect(page).to have_css(".checkin-result--error", text: "not confirmed")
    expect(page).to have_css("[data-checkin-target='count']", text: "0", exact_text: true)
    expect(page).to have_button("Review 1 selected ticket")
    expect(ticket.reload.checked_in_at).to be_empty
  end

  it "serializes repeat clicks and suppresses repeated camera frames while allowing the next QR" do
    first = create(:ticket, order:, attendee_name: "Test First")
    second = create(:ticket, order:, attendee_name: "Test Second")
    open_desk
    page.execute_script(<<~JS, first.secret)
      const controller = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller="checkin"]'), 'checkin');
      controller.scan(arguments[0]); controller.scan(arguments[0]);
    JS
    expect(page).to have_css(".checkin-result--success", text: "Test First")
    page.execute_script(<<~JS, second.secret)
      window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller="checkin"]'), 'checkin').scan(arguments[0]);
    JS
    expect(page).to have_css(".checkin-result--success", text: "Test Second")
    expect(CheckinAudit.where(outcome: "success").count).to eq(2)
    expect(CheckinAudit.where(outcome: "duplicate").count).to eq(0)
  end
end
