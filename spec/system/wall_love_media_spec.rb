require "rails_helper"

RSpec.describe "Wall of Love media journey", type: :system do
  it "starts with eighteen source cards and offers the complete collection and labeled filters" do
    visit wall_of_love_path
    within(".wall-love-collection") do
      expect(page).to have_css("[data-source-id]", count: 18)
      expect(page).to have_css("[data-source-id]", count: 54, visible: :all)
      expect(page).to have_content("Showing 18 of 54 sources")
      click_button "Load 18 more moments"
      expect(page).to have_css("[data-source-id]", count: 36)
      click_button "Load 18 more moments"
      expect(page).to have_css("[data-source-id]", count: 54)
      expect(page).not_to have_button("Load 18 more moments")
      select "Rails Girls", from: "Browse moments"
      expect(page).to have_css("[data-source-id]", count: 5)
      expect(page).to have_content("Related activity · Rails Girls")
      select "Watch the talks", from: "Browse moments"
      expect(page).to have_css("[data-source-id]", count: 4)
      expect(page).to have_link("Open original on YouTube ↗", count: 4)
    end
    expect(page).to have_css(".wall-love-recordings [data-recording-source-id]", count: 4)
  end

  it "supports manual keyboard navigation and stops optional rotation when navigating" do
    visit wall_of_love_path
    within(".wall-love-media") do
      expect(page).to have_css(".wall-love-media__slide", count: 1)
      expect(page).to have_content("1 / 14")
      click_button "Play slideshow"
      expect(page).to have_css('button[aria-pressed="true"]', text: "Pause slideshow")
      find('button[aria-label="Next featured source"]').click
      expect(page).to have_content("2 / 14")
      expect(page).to have_css('button[aria-pressed="false"]', text: "Play slideshow")
      find('button[aria-label="Next featured source"]').send_keys(:end)
      expect(page).to have_content("14 / 14")
      find('button[aria-label="Next featured source"]').send_keys(:home)
      expect(page).to have_content("1 / 14")
      expect(page).to have_link("Open original on X ↗", href: "https://x.com/marcoroth_/status/2108067887999336677")
    end
  end

  it "removes loaded players before a Turbo snapshot and requires a fresh click after Back" do
    visit wall_of_love_path
    within('[data-recording-source-id="S064"]') do
      click_button "Load recording player"
      expect(page).to have_css("iframe[src*='youtube-nocookie.com']")
    end
    find("a.nav-logo").click
    expect(page).to have_current_path(root_path)
    page.driver.browser.page.back
    expect(page).to have_current_path(wall_of_love_path)
    expect(page).to have_css("h1", text: "Wall of Love")
    expect(page).not_to have_css("iframe[src*='youtube-nocookie.com']")
    within('[data-recording-source-id="S064"]') do
      expect(page).to have_button("Load recording player")
      click_button "Load recording player"
      expect(page).to have_css("iframe[src*='youtube-nocookie.com/embed/a_pj2pci6iE'][src*='autoplay=0']")
    end
  end

  it "respects reduced motion and loads only one requested recording without autoplay" do
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit wall_of_love_path
    within(".wall-love-media") { expect(page).to have_button("Play slideshow", disabled: true) }
    expect(page).not_to have_css("iframe[src*='youtube-nocookie.com']")
    within('[data-recording-source-id="S064"]') do
      click_button "Load recording player"
      expect(page).to have_css("iframe[src*='youtube-nocookie.com/embed/a_pj2pci6iE'][src*='autoplay=0']")
      expect(page).to have_link("Watch original on YouTube ↗", href: "https://www.youtube.com/watch?v=a_pj2pci6iE")
    end
    within('[data-recording-source-id="S065"]') do
      click_button "Load recording player"
      expect(page).to have_css("iframe[src*='youtube-nocookie.com/embed/gxi9ZFuvuKw'][src*='autoplay=0']")
    end
    expect(page).to have_css("iframe[src*='youtube-nocookie.com']", count: 1)
    within('[data-recording-source-id="S064"]') { expect(page).to have_button("Load recording player") }
  ensure
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [])
  end
end
