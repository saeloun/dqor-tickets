require "rails_helper"

RSpec.describe "Schedule navigation", type: :system do
  let!(:talk) do
    Talk.create!(title: "Building reliable Rails applications", speaker_name: "Ada", published: true,
      starts_at: Time.utc(2026, 10, 8, 4, 0), ends_at: Time.utc(2026, 10, 8, 4, 30))
  end

  [
    [ "desktop header", "#nav-links", 1400, 1400 ],
    [ "mobile menu", "#nav-mobile-menu", 390, 844 ],
    [ "desktop footer", "footer", 1400, 1400 ],
    [ "mobile footer", "footer", 390, 844 ]
  ].each do |entry, scope, width, height|
    it "opens the full agenda from the #{entry} and returns to tickets with Back" do
      visit tickets_store_path
      page.current_window.resize_to(width, height)
      expect(page.evaluate_script("window.innerWidth")).to eq(width)
      find("#nav-mobile-toggle").click if scope == "#nav-mobile-menu"
      within scope do
        find_link("Schedule").execute_script("this.focus()")
      end
      page.driver.browser.keyboard.type(:enter)

      expect(page).to have_current_path(schedule_path)
      expect(page).to have_css("h1", text: "Conference schedule")
      expect(page).to have_css(".schedule-talk h3", text: talk.title)
      expect(page).to have_css("#nav-links a.active[href='#{schedule_path}']", visible: :all)
      expect(page).to have_no_css("#nav-mobile-menu.open")
      expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
      page.save_screenshot("schedule-navigation-#{entry.tr(' ', '-')}.png")

      page.go_back
      expect(page).to have_current_path(tickets_store_path)
      expect(page).to have_css("h1", text: "Choose your pass")
      expect(page).to have_no_css("#nav-mobile-menu.open")
      expect(page).to have_no_css("#nav-links a.active[href='#{schedule_path}']", visible: :all)
    ensure
      page.current_window.resize_to(1400, 1400)
    end
  end
end
