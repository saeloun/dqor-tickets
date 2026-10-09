require "rails_helper"

RSpec.describe "Conference venue directions", type: :system do
  [ 320, 390 ].each do |width|
    [ [ "/", "home" ], [ "/schedule", "schedule" ], [ "/tickets", "tickets" ] ].each do |path, name|
      it "shows the complete address and usable map links on #{name} at #{width}px" do
        page.driver.browser.resize(width: width, height: 844)
        visit path

        venue = find('.conference-venue[aria-label="Conference venue"]')
        expect(venue).to have_text("CONFERENCE · OCTOBER 8–9, 2026")
        expect(venue).to have_text("Hyatt Regency Pune & Residences")
        expect(venue).to have_text("Weikfield IT Park, Nagar Road, Pune 411014, Maharashtra, India")
        expect(venue).to have_link("Google Maps directions", href: /\Ahttps:\/\/www\.google\.com\/maps\/dir\//)
        expect(venue).to have_link("Apple Maps directions", href: /\Ahttps:\/\/maps\.apple\.com\/directions/)
        venue.scroll_to(:center)
        expect(page).to have_css(".conference-venue") { |node|
          page.evaluate_script(<<~JS, node)
            (() => {
              const venue = arguments[0];
              const bounds = venue.getBoundingClientRect();
              return bounds.top >= 0 && bounds.bottom <= innerHeight && bounds.left >= 0 && bounds.right <= innerWidth && [...venue.querySelectorAll('a')].every(link => {
                const rect = link.getBoundingClientRect();
                return rect.width >= 44 && rect.height >= 44 && rect.left >= bounds.left && rect.right <= bounds.right;
              });
            })()
          JS
        }
        expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
        page.save_screenshot(Rails.root.join("tmp/capybara/conference-venue-#{name}-#{width}.png"), full: false)
      end
    end
  end
end
