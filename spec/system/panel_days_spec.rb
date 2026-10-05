require "rails_helper"
require Rails.root.join("db/migrate/20261005110000_correct_conference_panel_days")

RSpec.describe "Corrected panel programme", type: :system do
  [ [ 1400, 1000 ], [ 390, 844 ] ].each do |width, height|
    it "keeps both panel links and exact time slots usable at #{width}px" do
      first = Talk.create!(id: 18, title: "Guest panel: Indian speakers", starts_at: Time.utc(2026, 10, 8, 9, 50), ends_at: Time.utc(2026, 10, 8, 10, 20), published: true, abstract: "Existing panel abstract")
      Talk.create!(id: 37, title: "Guest panel: international speakers", starts_at: Time.utc(2026, 10, 9, 9, 40), ends_at: Time.utc(2026, 10, 9, 10, 20), published: true)
      CorrectConferencePanelDays.new.up
      page.driver.resize(width, height)
      visit schedule_path
      within ".schedule-day", text: "Thursday, 8 October 2026" do
        expect(page).to have_text("3:20 PM – 3:50 PM")
        expect(page).to have_link("Guest panel: international speakers", href: talk_path(18))
        expect(page).not_to have_link("Guest panel: Indian speakers")
        click_link "Guest panel: international speakers"
      end
      expect(page).to have_current_path(talk_path(first))
      expect(page).to have_text("Guest panel: international speakers")
      expect(page).to have_text("Existing panel abstract")
      visit schedule_path
      within ".schedule-day", text: "Friday, 9 October 2026" do
        expect(page).to have_text("3:10 PM – 3:50 PM")
        expect(page).to have_link("Guest panel: Indian speakers", href: talk_path(37))
        expect(page).not_to have_link("Guest panel: international speakers")
      end
      if ENV["PANEL_EVIDENCE_DIR"].present?
        page.save_screenshot(File.join(ENV.fetch("PANEL_EVIDENCE_DIR"), "panel-after-#{width}.png"), full: true)
      end
      click_link "Guest panel: Indian speakers"
      expect(page).to have_current_path(talk_path(37))
      expect(page).to have_text("Guest panel: Indian speakers")
    ensure
      page.driver.resize(1400, 1400)
    end
  end
end
