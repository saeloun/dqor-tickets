require "rails_helper"

RSpec.describe "Camera self-test", type: :system do
  let(:operator) { create(:admin_user, role: :desk, password: "password123") }
  let!(:ticket) { create(:ticket, order: create(:order, :paid)) }

  def open_rehearsal
    visit scanner_rehearsal_path
    fill_in "email", with: operator.email
    fill_in "password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path(checkin_path)
    click_link "Camera self-test — no admission"
    expect(page).to have_content("REHEARSAL ONLY")
    expect(page).to have_button("Request Camera Permissions")
    page.execute_script(<<~JS)
      window.rehearsalRequests = [];
      window.originalRehearsalFetch = window.fetch.bind(window);
      window.fetch = (...args) => { window.rehearsalRequests.push(args[0]); return Promise.reject(new Error('Unexpected network request')); };
      XMLHttpRequest.prototype.send = function() { window.rehearsalRequests.push('XHR'); throw new Error('Unexpected XHR'); };
      navigator.sendBeacon = () => { window.rehearsalRequests.push('beacon'); return false; };
    JS
  end

  def expect_no_admission
    expect(page.evaluate_script("window.rehearsalRequests")).to eq([])
    expect(ticket.reload.checked_in_at).to be_empty
    expect(CheckinAudit.count).to eq(0)
    expect(EventSlotRedemption.count).to eq(0)
  end

  it "decodes the synthetic image through the real software decoder and rejects real QR contents locally" do
    paths = []
    page.driver.browser.resize(width: 375, height: 812)
    open_rehearsal
    page.execute_script("window.BarcodeDetector = undefined")
    find("span", text: "Scan an Image File", exact_text: true).click
    [ ScannerRehearsalsController::TEST_QR, ticket.secret ].each_with_index do |value, index|
      path = Rails.root.join("tmp", "rehearsal-#{index}.png")
      paths << path
      RQRCode::QRCode.new(value).as_png(size: 360).save(path)
      find("input[type='file']", visible: :all).set(path)
      expected = index.zero? ? "QR decoder recognized the synthetic sample" : "Unrecognized sample"
      expect(page).to have_css('[data-scanner-rehearsal-target="result"]', text: expected)
      expect_no_admission
    end
    expect(page).to have_no_content(ticket.attendee_email)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
  ensure
    paths&.each { |path| File.delete(path) if File.exist?(path) }
  end

  it "enforces the page policy against an accidental attendance request" do
    open_rehearsal
    page.execute_script(<<~JS, ticket.secret)
      window.originalRehearsalFetch('/checkin', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ secret: arguments[0], date: '2026-10-08' })
      }).then(() => document.body.dataset.connectionBlocked = 'false',
        () => document.body.dataset.connectionBlocked = 'true');
    JS
    expect(page).to have_css('body[data-connection-blocked="true"]')
    expect_no_admission
  end

  it "keeps permission requests explicit and manual fallback local after denial" do
    open_rehearsal
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
    fill_in "Synthetic test text", with: ScannerRehearsalsController::TEST_QR
    click_button "Test manual fallback"
    expect(page).to have_content("Manual fallback (camera not tested) recognized the synthetic sample")
    expect_no_admission
  end

  it "suppresses callbacks after rotation/background and resumes only after explicit restart" do
    open_rehearsal
    [ "orientationchange", "visibilitychange" ].each do |event|
      page.execute_script(<<~JS, event, ScannerRehearsalsController::TEST_QR)
        const controller = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller="scanner-rehearsal"]'), 'scanner-rehearsal');
        if (arguments[0] === 'visibilitychange') {
          Object.defineProperty(document, 'hidden', { configurable: true, value: true });
          document.dispatchEvent(new Event('visibilitychange'));
          Object.defineProperty(document, 'hidden', { configurable: true, value: false });
        } else { window.dispatchEvent(new Event(arguments[0])); }
        controller.scan(arguments[1]);
      JS
      expect(page).to have_content("Camera paused after leaving the page or rotating your phone")
      expect(page).to have_css('[data-scanner-rehearsal-target="result"]', text: "No test result yet.")
      click_button "Restart camera"
      expect(page).to have_button("Request Camera Permissions")
    end
    expect_no_admission
  end
end
