require "rails_helper"

RSpec.describe "Mobile slot views", type: :system do
  it "shows purpose prominently and verified own status without overflow" do
    operator = create(:admin_user, password: "password123")
    slot = EventSlot.create!(name: "Synthetic Day1 food", starts_at: Time.utc(2026, 10, 8, 6), ends_at: Time.utc(2026, 10, 8, 9))
    page.driver.browser.resize(width: 375, height: 812)
    visit event_slot_path(slot)
    fill_in "email", with: operator.email
    fill_in "password", with: "password123"
    click_button "Sign in"
    expect(page).to have_content("Scanning: Synthetic Day1 food")
    expect(page).to have_content("Draft — redemption disabled")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    user = User.create!(email: "mobile@example.test")
    create(:ticket, order: create(:order, :paid), attendee_email: user.email, checked_in_at: { "2026-10-08" => "2026-10-08T07:00:00Z" })
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token: token)
    visit account_redemptions_path
    expect(page).to have_content("2026-10-08T07:00:00Z")
    page.execute_script("window.dispatchEvent(new Event('offline'))")
    expect(page).to have_content("may be stale")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
  end
end

RSpec.describe "Slot scanner recovery", type: :system do
  it "supports manual lookup after interruption and safely retries an uncertain response" do
    operator = create(:admin_user, role: :desk, password: "password123")
    ticket = create(:ticket, attendee_name: "Synthetic Lookup", order: create(:order, :paid))
    slot = EventSlot.create!(name: "Synthetic lunch", starts_at: Time.utc(2026, 10, 8, 6), ends_at: Time.utc(2026, 10, 8, 9), active: true, ticket_type_ids: [ ticket.ticket_type_id ])
    travel_to(Time.utc(2026, 10, 8, 7)) do
      page.driver.browser.resize(width: 375, height: 812)
      visit event_slot_path(slot)
      fill_in "email", with: operator.email
      fill_in "password", with: "password123"
      click_button "Sign in"
      expect(page).to have_current_path(checkin_path)
      visit event_slot_path(slot)
      expect(page).to have_content("Scanning: Synthetic lunch")
      page.execute_script("window.dispatchEvent(new Event('orientationchange'))")
      expect(page).to have_content("Camera paused after leaving")
      click_button "Restart camera"
      expect(page).to have_content("Allow camera access")
      fill_in "q", with: "Synthetic Lookup"
      click_button "Search attendees"
      expect(page).to have_button("Redeem Synthetic lunch for Synthetic Lookup")
      page.execute_script(<<~JS)
        window.slotOriginalFetch = window.fetch;
        window.fetch = async (...args) => { await window.slotOriginalFetch(...args); throw new TypeError('synthetic lost response after commit'); };
      JS
      click_button "Redeem Synthetic lunch for Synthetic Lookup"
      expect(page).to have_content("Not confirmed")
      expect(EventSlotRedemption.where(ticket: ticket).count).to eq(1)
      page.execute_script("window.fetch = window.slotOriginalFetch")
      click_button "Retry last unconfirmed scan"
      expect(page).to have_content("Synthetic lunch: redeemed at")
      expect(EventSlotRedemption.where(ticket: ticket).count).to eq(1)
      expect(ticket.reload.checked_in_at).to eq({})
      expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    end
  end
end

RSpec.describe "Slot software QR fallback", type: :system do
  it "redeems the preserved CI-failing QR without BarcodeDetector or consuming admission" do
    operator = create(:admin_user, password: "password123")
    ticket = create(:ticket, order: create(:order, :paid), secret: Rails.root.join("spec/fixtures/checkin_software_decoder_secret.txt").read.strip)
    slot = EventSlot.create!(name: "Synthetic QR meal", starts_at: Time.utc(2026, 10, 8, 6), ends_at: Time.utc(2026, 10, 8, 9), active: true, ticket_type_ids: [ ticket.ticket_type_id ])
    image_path = Rails.root.join("tmp", "slot-fallback-#{ticket.id}.png")
    RQRCode::QRCode.new(ticket.secret).as_png(size: 360).save(image_path)
    travel_to(Time.utc(2026, 10, 8, 7)) do
      visit event_slot_path(slot)
      fill_in "email", with: operator.email
      fill_in "password", with: "password123"
      click_button "Sign in"
      expect(page).to have_content("Scanning: Synthetic QR meal")
      page.execute_script("window.BarcodeDetector = undefined")
      find("span", text: "Scan an Image File", exact_text: true).click
      find("input[type='file']", visible: :all).set(image_path)
      expect(page).to have_content("Synthetic QR meal: redeemed at")
      expect(EventSlotRedemption.where(event_slot: slot, ticket: ticket).count).to eq(1)
      expect(ticket.reload.checked_in_at).to eq({})
    end
  ensure
    File.delete(image_path) if image_path && File.exist?(image_path)
  end
end
