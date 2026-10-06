require "rails_helper"

RSpec.describe "Premium attendee journeys", type: :system do
  it "keeps the event and navigation readable at 320px with reduced motion" do
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    page.driver.browser.resize(width: 320, height: 740)
    attendee = User.create!(email: "hero-layout@example.com", name: "Synthetic Hero Guest", public_attendee: true)
    File.open(Rails.root.join("public/dqor/deccan-logo.png")) do |avatar|
      attendee.avatar.attach(io: avatar, filename: "synthetic-avatar.png", content_type: "image/png")
    end
    create(:ticket, order: create(:order, :paid), attendee_name: attendee.name, attendee_email: attendee.email)
    visit root_path
    expect(page).to have_css(".hero-heading", text: "Deccan Queen")
    expect(page).to have_link("Explore the schedule")
    expect(page).to have_css(".whos-coming__count", text: "1 Rails Developers attending")
    expect(page).to have_css(".whos-coming__face", count: 1)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    expect(page.evaluate_script("getComputedStyle(document.querySelector('.hero')).backgroundImage")).to include("/dqor/hero-bg.jpg")
    expect(page).to have_css(".hero-logo[src='/dqor/deccan-logo.png']")
    expect(page).to have_link("Get your pass →", href: tickets_store_path)
    expect(page).to have_link("Add to calendar", href: calendar_path)
    expect(page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.hero-heading')).animationDuration)")).to be <= 0.00001
    expect(page.evaluate_script("document.querySelector('.hero-logo').complete && document.querySelector('.hero-logo').naturalWidth > 0")).to be(true)
    [ [ 320, 740 ], [ 390, 844 ], [ 640, 360 ], [ 1400, 700 ], [ 1024, 768 ] ].each do |width, height|
      page.driver.browser.resize(width: width, height: height)
      page.execute_script("window.scrollTo(0, 0)")
      bounds = page.evaluate_script(<<~JS)
        (() => {
          const hero = document.querySelector('#hero').getBoundingClientRect();
          const nav = document.querySelector('#main-nav').getBoundingClientRect();
          const controls = [...document.querySelectorAll('.hero-logo, .hero-actions a, .hero-socials a, .whos-coming, .whos-coming__face')]
            .filter(element => element.getClientRects().length > 0)
            .map(element => ({ top: element.getBoundingClientRect().top, bottom: element.getBoundingClientRect().bottom }));
          return { heroTop: hero.top, heroBottom: hero.bottom, navBottom: nav.bottom, controls };
        })()
      JS
      aggregate_failures("#{width}x#{height} hero controls") do
        expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
        expect(bounds.fetch("controls")).not_to be_empty
        bounds.fetch("controls").each do |control|
          expect(control.fetch("top")).to be >= [ bounds.fetch("heroTop"), bounds.fetch("navBottom") ].max
          expect(control.fetch("bottom")).to be <= bounds.fetch("heroBottom")
        end
      end
    end
    page.driver.browser.resize(width: 320, height: 740)
    page.save_screenshot(Rails.root.join("tmp/premium-home-reduced-320.png"))
    click_link "Explore the schedule"
    expect(page).to have_content("Conference schedule")
    expect(page).to have_content("The schedule is being finalised")
    page.go_back
    expect(page).to have_css(".hero-heading", text: "Deccan Queen")
  end

  it "saves once under repeated taps, opens a talk, and recovers the saved schedule after offline navigation" do
    user = User.create!(email: "premium-browser@example.com", name: "Synthetic Guest")
    talk = Talk.create!(title: "Synthetic programme browser test", abstract: "A local-only journey fixture.", speaker_name: "Synthetic Speaker", published: true, starts_at: Time.utc(2026, 10, 8, 4), ends_at: Time.utc(2026, 10, 8, 4, 30), room: "Local test room")
    visit account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
    visit schedule_path
    page.driver.browser.resize(width: 390, height: 844)
    page.driver.browser.network.emulate_network_conditions(latency: 300, download_throughput: 1_000_000, upload_throughput: 1_000_000)
    within(".schedule-talk", text: talk.title) do
      page.execute_script("const b = document.querySelector('.schedule-talk__save'); b.click(); b.click()")
      expect(page).to have_button("★ Saved")
    end
    expect(user.talk_bookmarks.where(talk: talk).count).to eq(1)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    page.save_screenshot(Rails.root.join("tmp/premium-programme-mobile.png"), full: true)
    click_link talk.title
    expect(page).to have_content("Audience questions")
    page.save_screenshot(Rails.root.join("tmp/premium-talk-mobile.png"), full: true)
    click_link "← Schedule"
    expect(page).to have_button("★ Saved")
    page.driver.browser.network.offline_mode
    expect { visit account_root_path }.to raise_error(Ferrum::StatusError)
    expect(user.talk_bookmarks.where(talk: talk).count).to eq(1)
    page.driver.browser.network.emulate_network_conditions
    visit account_root_path
    within("section", text: "My schedule") do
      expect(page).to have_link(talk.title)
    end
    visit schedule_path
    click_button "★ Saved"
    expect(page).to have_button("☆ Save to my schedule")
    expect(user.talk_bookmarks.where(talk: talk)).to be_empty
  ensure
    page.driver.browser.network.emulate_network_conditions
  end
end
