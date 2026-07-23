require "rails_helper"

Capybara.register_driver(:cuprite_camera) do |app|
  options = {
    window_size: [ 1400, 1400 ],
    process_timeout: 30,
    timeout: 20,
    headless: true,
    js_errors: true,
    browser_options: {
      "use-fake-ui-for-media-stream": nil,
      "use-fake-device-for-media-stream": nil
    }
  }
  options[:browser_path] = ENV["CHROME_PATH"] if ENV["CHROME_PATH"].present?
  options[:browser_options].merge!("no-sandbox": nil, "disable-dev-shm-usage": nil) if ENV["CHROME_NO_SANDBOX"].present?

  Capybara::Cuprite::Driver.new(app, **options)
end

RSpec.describe "Check-in", type: :system do
  let(:admin) { create(:admin_user, password: "password123") }

  before { driven_by :cuprite_camera }

  around do |example|
    forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    travel_to(Time.utc(2026, 7, 1, 9, 0)) { example.run }
    ActionController::Base.allow_forgery_protection = forgery_protection
  end

  def sign_in(admin_user = admin)
    visit new_session_path
    fill_in "email", with: admin_user.email
    fill_in "password", with: "password123"
    click_button "Sign in"
  end

  def open_desk
    visit checkin_path
    sign_in
    expect(page).to have_content("Attendee check-in")
  end

  def start_scanner
    click_button "Request Camera Permissions"
    expect(page).to have_css("#checkin-reader canvas", visible: :all, wait: 15)
  end

  def await_scanner
    expect(page).to have_no_text("Scanner paused", wait: 15)
  end

  def search_for(query)
    fill_in "q", with: query
    click_button "Search"
    start_scanner
  end

  def check_in(ticket)
    find("button[data-secret='#{ticket.secret}']").click
  end

  it "redirects an unauthenticated visitor to the sign-in page" do
    visit checkin_path

    expect(page).to have_current_path(new_session_path)
    expect(page).to have_button("Sign in")
  end

  it "returns to the check-in desk after signing in" do
    visit checkin_path
    sign_in

    expect(page).to have_current_path(checkin_path)
    expect(page).to have_content("Attendee check-in")
  end

  it "checks in a ticket found by attendee name" do
    ticket = create(:ticket, attendee_name: "Grace Hopper")

    open_desk
    search_for("grace")

    expect(page).to have_content("Grace Hopper")
    check_in(ticket)

    expect(page).to have_css(".checkin-result--success", text: "Checked in Grace Hopper")
    expect(ticket.reload.checked_in_at).to have_key("2026-10-08")
  end

  it "finds a ticket by its order code and names the attendee on success" do
    ticket = create(:ticket, attendee_name: "Alan Turing")

    open_desk
    search_for(ticket.order.code)

    check_in(ticket)

    expect(page).to have_css(".checkin-result--success", text: "Checked in Alan Turing")
  end

  it "falls back to the attendee email when the ticket has no name" do
    ticket = create(:ticket, attendee_name: nil, attendee_email: "unnamed@example.com")

    open_desk
    search_for("unnamed@example.com")

    expect(page).to have_content("Unnamed attendee")
    check_in(ticket)

    expect(page).to have_css(".checkin-result--success", text: "Checked in unnamed@example.com")
  end

  it "warns with the original time when one ticket is checked in twice on the same date" do
    ticket = create(:ticket, attendee_name: "Katherine Johnson")

    open_desk
    search_for("katherine")

    check_in(ticket)
    expect(page).to have_css(".checkin-result--success")

    time = Time.iso8601(ticket.reload.checked_in_at.fetch("2026-10-08"))
      .in_time_zone("Asia/Kolkata").strftime("%H:%M")

    await_scanner
    check_in(ticket)

    expect(page).to have_css(".checkin-result--warning", text: "Already checked in at #{time}")
    expect(ticket.reload.checked_in_at.keys).to eq([ "2026-10-08" ])
  end

  it "allows the same ticket to be checked in again on another event date" do
    ticket = create(:ticket, attendee_name: "Barbara Liskov")

    open_desk
    search_for("barbara")

    check_in(ticket)
    expect(page).to have_css(".checkin-result--success")
    await_scanner

    select "Oct 9", from: "date"
    check_in(ticket)

    expect(page).to have_css(".checkin-result--success", text: "Checked in Barbara Liskov")
    expect(ticket.reload.checked_in_at.keys).to match_array([ "2026-10-08", "2026-10-09" ])
  end

  it "refuses to check in a canceled ticket" do
    ticket = create(:ticket, attendee_name: "Ada Lovelace", canceled_at: Time.current)

    open_desk
    search_for("ada")

    check_in(ticket)

    expect(page).to have_css(".checkin-result--error", text: "Canceled or refunded ticket")
    expect(ticket.reload.checked_in_at).to be_empty
  end

  it "reports a not-found error for an unknown ticket secret" do
    ticket = create(:ticket, attendee_name: "Margaret Hamilton")

    open_desk
    search_for("margaret")

    page.execute_script(<<~JS, ticket.secret)
      document.querySelector(`button[data-secret="${arguments[0]}"]`).dataset.secret = "not-a-real-secret"
    JS
    find("button[data-secret='not-a-real-secret']").click

    expect(page).to have_css(".checkin-result--error", text: "Ticket not found")
    expect(ticket.reload.checked_in_at).to be_empty
  end

  it "keeps the chosen event date across a search" do
    create(:ticket, attendee_name: "Rear Admiral")

    visit checkin_path
    sign_in

    select "Oct 10", from: "date"
    fill_in "q", with: "rear"
    click_button "Search"

    expect(page).to have_select("date", selected: "Oct 10")
    expect(page).to have_content("Rear Admiral")
  end

  it "falls back to the first event day when the date param is garbage" do
    sign_in
    visit checkin_path(date: "garbage")

    expect(page).to have_select("date", selected: "Oct 8")
  end

  describe "on a device with no camera" do
    before { driven_by :cuprite }

    it "still checks in from the search results when no scanner is running" do
      ticket = create(:ticket, order: create(:order, :paid), attendee_name: "Grace Hopper")

      visit checkin_path
      sign_in
      fill_in "q", with: "Grace"
      click_button "Search"
      find("button[data-secret='#{ticket.secret}']").click

      expect(page).to have_css(".checkin-result--success", text: "Checked in Grace Hopper")
      expect(ticket.reload.checked_in_at).to have_key("2026-10-08")
    end
  end
end
