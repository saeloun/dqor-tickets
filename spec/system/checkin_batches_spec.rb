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
    expect(page).to have_button("Request Camera Permissions")
  end

  it "opens only the Avo selection without recording attendance" do
    operator.update!(role: :admin)
    selected = create(:ticket, order:, attendee_name: "Selected Attendee")
    create(:ticket, order:, attendee_name: "Other Attendee")
    open_desk
    visit "/avo/resources/tickets"
    # A visible checkbox can precede Stimulus connection; wait for the actual
    # selector controller before interacting, then verify its retained state.
    expect(page).to have_css('[data-controller~="item-selector"]') { |node|
      page.evaluate_script("Boolean(window.Stimulus?.getControllerForElementAndIdentifier(arguments[0], 'item-selector')?.stateHolderElement)", node)
    }
    within("tr", text: "Selected Attendee") do
      check "Select item"
      expect(page).to have_checked_field("Select item")
    end
    expect(page).to have_css("[data-selected-resources='[\"#{selected.id}\"]']")
    click_button "Actions"
    expect(page).to have_css('a[data-disabled="false"]', text: "Check in selected tickets")
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

  it "recovers a batch response lost after commit without admitting or counting twice" do
    ticket = create(:ticket, order:, attendee_name: "Synthetic Lost Response")
    page.driver.browser.resize(width: 390, height: 844)
    open_desk
    click_button "Select shown tickets"
    click_button "Review 1 selected ticket"
    page.execute_script(<<~JS)
      window.originalBatchFetch = window.fetch.bind(window);
      window.batchResponseDiscarded = false;
      window.fetch = async (...args) => {
        const response = await window.originalBatchFetch(...args);
        if (args[0] === '/checkin/batch' && !window.batchResponseDiscarded) {
          window.batchResponseDiscarded = true;
          throw new TypeError('synthetic response lost after commit');
        }
        return response;
      };
    JS
    click_button "Confirm check-in"
    expect(page).to have_css(".checkin-result--error", text: "not confirmed")
    expect(page).to have_css("[data-checkin-target='count']", text: "0", exact_text: true)
    expect(page).to have_button("Review 1 selected ticket")
    original = ticket.reload.checked_in_at
    expect(original.keys).to eq([ "2026-10-08" ])
    expect(CheckinAudit.where(ticket:, outcome: "success").count).to eq(1)
    page.save_screenshot(Rails.root.join("tmp/capybara/scanner-response-lost-after-commit.png"), full: true)

    click_button "Review 1 selected ticket"
    click_button "Confirm check-in"
    expect(page).to have_css("[aria-label='Batch results']", text: "Already checked in")
    expect(page).to have_css("[data-checkin-target='count']", text: "1", exact_text: true)
    expect(page).to have_button("Review 0 selected tickets", disabled: true)
    expect(ticket.reload.checked_in_at).to eq(original)
    expect(CheckinAudit.where(ticket:).pluck(:outcome)).to match_array(%w[success duplicate])
    expect(CheckinAudit.where(ticket:, outcome: "success").count).to eq(1)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/capybara/scanner-response-recovered-once.png"), full: true)
  end

  it "refuses a reviewed batch when the staff session expires before confirmation" do
    ticket = create(:ticket, order:, attendee_name: "Synthetic Expired Session")
    page.driver.browser.resize(width: 390, height: 844)
    open_desk
    click_button "Select shown tickets"
    click_button "Review 1 selected ticket"
    expect(page).to have_css("dialog[open]", text: ticket.attendee_name)
    operator.sessions.destroy_all
    expect(operator.sessions.count).to eq(0)

    click_button "Confirm check-in"
    expect(page).to have_css(".checkin-result--error", text: "Session expired. Sign in before checking in.")
    expect(page).to have_css("[data-checkin-target='count']", text: "0", exact_text: true)
    expect(page).to have_button("Review 1 selected ticket")
    expect(page).to have_no_css("[aria-label='Batch results'] li")
    expect(ticket.reload.checked_in_at).to eq({})
    expect(CheckinAudit.count).to eq(0)
    page.save_screenshot(Rails.root.join("tmp/capybara/scanner-expired-session-no-admission.png"), full: true)
  end

  it "decodes a QR image without BarcodeDetector using the bundled software decoder" do
    ticket = create(:ticket, order:, attendee_name: "Software Decoder", secret: Rails.root.join("spec/fixtures/checkin_software_decoder_secret.txt").read.strip)
    image_path = Rails.root.join("tmp", "checkin-fallback-#{ticket.id}.png")
    RQRCode::QRCode.new(ticket.secret).as_png(size: 360).save(image_path)
    open_desk
    page.execute_script("window.BarcodeDetector = undefined")
    find("span", text: "Scan an Image File", exact_text: true).click
    find("input[type='file']", visible: :all).set(image_path)
    expect(page).to have_css(".checkin-result--success", text: "Software Decoder")
    expect(ticket.reload.checked_in_at).to have_key("2026-10-08")
  ensure
    File.delete(image_path) if image_path && File.exist?(image_path)
  end

  it "decodes varied QR payloads and sizes while rejecting a blank image" do
    payloads = [ "A" * 24, "123456789ABCDEFGHijkmnopq", "z5KfL9yTp2Ax7Hs3Bn8Mq4Rv" ]
    paths = []
    open_desk
    page.execute_script("window.BarcodeDetector = undefined")
    find("span", text: "Scan an Image File", exact_text: true).click
    blank_path = Rails.root.join("tmp", "checkin-blank.png")
    paths << blank_path
    ChunkyPNG::Image.new(300, 300, ChunkyPNG::Color::WHITE).save(blank_path)
    find("input[type='file']", visible: :all).set(blank_path)
    expect(page).to have_content("No MultiFormat Readers")
    expect(CheckinAudit.count).to eq(0)
    payloads.zip([ 240, 360, 600 ]).each_with_index do |(secret, size), index|
      ticket = create(:ticket, order:, attendee_name: "QR Corpus #{index}", secret:)
      image_path = Rails.root.join("tmp", "checkin-corpus-#{index}.png")
      paths << image_path
      RQRCode::QRCode.new(secret).as_png(size:).save(image_path)
      find("input[type='file']", visible: :all).set(image_path)
      expect(page).to have_css(".checkin-result--success", text: "QR Corpus #{index}")
      expect(ticket.reload.checked_in_at).to have_key("2026-10-08")
    end
    expect(CheckinAudit.where(outcome: "success").count).to eq(3)
  ensure
    paths&.each { |path| File.delete(path) if File.exist?(path) }
  end

  it "keeps denied camera permission user-driven and manual check-in available" do
    ticket = create(:ticket, order:, attendee_name: "Manual Fallback")
    open_desk
    page.execute_script(<<~JS)
      window.cameraRequests = 0;
      navigator.mediaDevices.getUserMedia = () => {
        window.cameraRequests += 1;
        return Promise.reject(new DOMException('Permission denied', 'NotAllowedError'));
      };
    JS
    expect(page.evaluate_script("window.cameraRequests")).to eq(0)
    click_button "Request Camera Permissions"
    expect(page).to have_content("Permission denied")
    expect(page.evaluate_script("window.cameraRequests")).to eq(1)
    expect(page).to have_content("use attendee search below")
    find("button[data-ticket-id='#{ticket.id}']").click
    expect(page).to have_css(".checkin-result--success", text: "Manual Fallback")
  end

  it "pauses scans after phone rotation and requires an explicit restart" do
    ticket = create(:ticket, order:, attendee_name: "Rotation Test")
    open_desk
    page.execute_script(<<~JS, ticket.secret)
      window.dispatchEvent(new Event('orientationchange'));
      window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller="checkin"]'), 'checkin').scan(arguments[0]);
    JS
    expect(page).to have_content("Camera paused after leaving the page or rotating your phone")
    expect(ticket.reload.checked_in_at).to be_empty
    click_button "Restart camera"
    expect(page).to have_button("Request Camera Permissions")
    expect(page).to have_content("choose the back/rear camera")
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
