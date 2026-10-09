require "rails_helper"

RSpec.describe "Scanner result visibility", type: :system do
  let(:operator) { create(:admin_user, role: :desk, password: "password123") }
  let(:ticket) { create(:ticket, ticket_type: create(:ticket_type, slug: "conference-pass-regular"), order: create(:order, :paid), attendee_name: "Synthetic Camera Result") }

  after do
    @image_paths&.each { |path| File.delete(path) if File.exist?(path) }
  end

  def open_desk
    ticket
    page.driver.browser.resize(width: 390, height: 600)
    visit checkin_path
    fill_in "email", with: operator.email
    fill_in "password", with: "password123"
    click_button "Sign in"
    expect(page).to have_button("Request Camera Permissions")
    select "Oct 8", from: "date" unless find(:select, "date").value == "2026-10-08"
    expect(page).to have_css(".checkin-stat__label", text: "checked in · Thu Oct 8", exact_text: true)
    expect(page).to have_no_css('[data-controller="checkin"][aria-busy="true"]')
    expect(page).to have_button("Request Camera Permissions")
    expect(page).to have_select("date", selected: "Oct 8")
  end

  def decode_image
    path = Rails.root.join("tmp", "scanner-result-#{ticket.id}.png")
    (@image_paths ||= []) << path
    RQRCode::QRCode.new(ticket.secret).as_png(size: 360).save(path)
    find("span", text: "Scan an Image File", exact_text: true).click
    find("input[type='file']", visible: :all).set(path)
  end

  it "brings a real software-decoded server result into the phone viewport and focus" do
    open_desk
    decode_image
    expect(page).to have_css(".checkin-result--success", text: "Checked in Synthetic Camera Result")
    dimensions = page.evaluate_script("(() => { const r = document.querySelector('[data-checkin-target=\"result\"]'); const b = r.getBoundingClientRect(); return { focused: document.activeElement === r, top: b.top, bottom: b.bottom, viewport: innerHeight }; })()")
    puts "Scanner viewport geometry: #{dimensions.inspect}"
    page.save_screenshot(Rails.root.join("tmp/capybara/scanner-result-before-geometry.png"), full: false)
    expect(page.evaluate_script(<<~JS)).to be(true)
      (() => {
        const result = document.querySelector('[data-checkin-target="result"]');
        const bounds = result.getBoundingClientRect();
        return document.activeElement === result && bounds.top >= -1 && bounds.bottom <= innerHeight + 1;
      })()
    JS
    expect(CheckinAudit.where(ticket:, outcome: "success").count).to eq(1)
    page.save_screenshot(Rails.root.join("tmp/capybara/scanner-result-visible.png"), full: false)
  end

  it "shows explicit restart guidance when a decoded image arrives after interruption without admitting" do
    open_desk
    page.execute_script("window.dispatchEvent(new Event('orientationchange'))")
    decode_image
    expect(page).to have_css(".checkin-result--warning", text: "Camera paused")
    expect(page).to have_css(".checkin-result--warning", text: "Restart camera")
    expect(ticket.reload.checked_in_at).to eq({})
    expect(CheckinAudit.count).to eq(0)
    click_button "Restart camera"
    expect(page).to have_button("Request Camera Permissions")
    page.execute_script("window.dispatchEvent(new Event('orientationchange'))")
    page.execute_script(<<~JS, ticket.secret)
      const controller = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller="checkin"]'), 'checkin');
      controller.scan(arguments[0]);
      document.querySelector('[data-action="checkin#restartCamera"]').focus();
      for (let index = 0; index < 10; index++) controller.scan(arguments[0]);
    JS
    expect(page.evaluate_script("document.activeElement.dataset.action")).to eq("checkin#restartCamera")
    expect(ticket.reload.checked_in_at).to eq({})
    expect(CheckinAudit.count).to eq(0)
    page.save_screenshot(Rails.root.join("tmp/capybara/scanner-interrupted-visible.png"), full: false)
  end

  it "safely retries the same decoded QR after a response is lost following server commit" do
    open_desk
    page.execute_script(<<~JS)
      const fetch = window.fetch.bind(window);
      window.responseLost = false;
      window.fetch = async (...args) => {
        const response = await fetch(...args);
        if (args[0] === '/checkin' && !window.responseLost) {
          window.responseLost = true;
          throw new TypeError('synthetic response lost after commit');
        }
        return response;
      };
    JS
    decode_image
    expect(page).to have_css(".checkin-result--error", text: "not confirmed")
    expect(page).to have_css("[data-checkin-target='count']", text: "0", exact_text: true)
    original = ticket.reload.checked_in_at
    expect(original.keys).to eq([ "2026-10-08" ])
    page.execute_script(<<~JS, ticket.secret)
      window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller="checkin"]'), 'checkin').scan(arguments[0]);
    JS
    expect(page).to have_css(".checkin-result--warning", text: "Already checked in")
    expect(page).to have_css("[data-checkin-target='count']", text: "1", exact_text: true)
    expect(ticket.reload.checked_in_at).to eq(original)
    page.save_screenshot(Rails.root.join("tmp/capybara/scanner-safe-retry-visible.png"), full: false)
    expect(CheckinAudit.where(ticket:).pluck(:outcome)).to match_array(%w[success duplicate])
    expect(CheckinAudit.where(ticket:, outcome: "success").count).to eq(1)
  end

  it "verifies the same camera QR again after native date navigation and Turbo back navigation" do
    open_desk
    decode_image
    expect(page).to have_css(".checkin-result--success", text: "Synthetic Camera Result")
    select "Oct 9", from: "date"
    expect(page).to have_css(".checkin-stat__label", text: "checked in · Fri Oct 9", exact_text: true)
    expect(page).to have_no_css('[data-controller="checkin"][aria-busy="true"]')
    expect(page).to have_button("Request Camera Permissions")
    expect(page).to have_select("date", selected: "Oct 9")
    decode_image
    expect(page).to have_css(".checkin-result--success", text: "Synthetic Camera Result")
    expect(ticket.reload.checked_in_at.keys).to match_array([ "2026-10-08", "2026-10-09" ])
    page.go_back
    expect(page).to have_css(".checkin-stat__label", text: "checked in · Thu Oct 8", exact_text: true)
    expect(page).to have_no_css('[data-controller="checkin"][aria-busy="true"]')
    expect(page).to have_button("Request Camera Permissions")
    expect(page).to have_select("date", selected: "Oct 8")
    page.execute_script(<<~JS, ticket.secret)
      window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller="checkin"]'), 'checkin').scan(arguments[0]);
    JS
    expect(page).to have_css(".checkin-result--warning", text: "Already checked in")
    expect(CheckinAudit.where(ticket:, outcome: "success").count).to eq(2)
  end

  it "retains the confirmed result when the same camera QR remains in view beyond three seconds" do
    open_desk
    decode_image
    expect(page).to have_css(".checkin-result--success", text: "Synthetic Camera Result")
    page.execute_script(<<~JS, ticket.secret)
      const fetch = window.fetch.bind(window);
      window.repeatedFrameRequests = 0;
      window.fetch = (...args) => { window.repeatedFrameRequests += 1; return fetch(...args); };
      const now = Date.now.bind(Date);
      Date.now = () => now() + 4000;
      const controller = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller="checkin"]'), 'checkin');
      controller.scan(arguments[0]);
    JS
    expect(page).to have_css(".checkin-result--success", text: "Synthetic Camera Result")
    expect(page.evaluate_script("window.repeatedFrameRequests")).to eq(0)
    expect(page).to have_no_css(".checkin-result--warning", text: "Already checked in")
    expect(CheckinAudit.where(ticket:).count).to eq(1)
    find("button[data-ticket-id='#{ticket.id}']").click
    expect(page).to have_css(".checkin-result--warning", text: "Already checked in")
    expect(CheckinAudit.where(ticket:, outcome: "success").count).to eq(1)
  end
  [ "manual", "batch" ].each do |replacement|
    it "verifies camera A again after #{replacement} B replaces its result" do
      other = create(:ticket, ticket_type: ticket.ticket_type, order: ticket.order, attendee_name: "Synthetic Other Attendee")
      open_desk
      decode_image
      expect(page).to have_css(".checkin-result--success", text: "Synthetic Camera Result")
      original = ticket.reload.checked_in_at
      if replacement == "manual"
        find("button[data-ticket-id='#{other.id}']").click
        expect(page).to have_css(".checkin-result--success", text: "Synthetic Other Attendee")
      else
        find("input[data-checkin-target='selection'][value='#{other.id}']").check
        click_button "Review 1 selected ticket"
        click_button "Confirm check-in"
        expect(page).to have_css("[aria-label='Batch results']", text: "Checked in Synthetic Other Attendee")
        expect(page).to have_css(".checkin-result--success", text: "1 checked in")
      end
      page.execute_script(<<~JS, ticket.secret)
        const fetch = window.fetch.bind(window);
        window.transitionRequests = [];
        window.transitionResponse = null;
        window.fetch = async (...args) => {
          const payload = JSON.parse(args[1].body);
          window.transitionRequests.push(payload.secret);
          const response = await fetch(...args);
          window.transitionResponse = await response.clone().json();
          return response;
        };
        window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller="checkin"]'), 'checkin').scan(arguments[0]);
      JS
      expect(page).to have_css(".checkin-result--warning", text: "Already checked in")
      expect(page.evaluate_script("window.transitionRequests")).to eq([ ticket.secret ])
      expect(page.evaluate_script("window.transitionResponse.ticket_id")).to eq(ticket.id)
      expect(page.evaluate_script("window.transitionResponse.attendee")).to eq(ticket.attendee_name)
      expect(page).to have_no_css("[data-checkin-target='result']", text: "Synthetic Other Attendee")
      expect(ticket.reload.checked_in_at).to eq(original)
      expect(CheckinAudit.where(ticket:, outcome: "success").count).to eq(1)
      expect(CheckinAudit.where(ticket:, outcome: "duplicate").count).to eq(1)
      expect(CheckinAudit.where(ticket: other, outcome: "success").count).to eq(1)
      page.save_screenshot(Rails.root.join("tmp/capybara/scanner-after-#{replacement}-visible.png"), full: false)
    end
  end
end
