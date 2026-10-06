require "rails_helper"

RSpec.describe "Event website organizer journey", type: :system do
  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
  end

  def sign_in_verified(user)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token:)
    expect(page).to have_current_path(/\A\/(?:account|free\/tickets)/)
  end

  def expect_no_horizontal_overflow
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
  end

  def expect_registration_contrast
    controls = page.evaluate_script(<<~JS)
      [...document.querySelectorAll('.event-website .ew-button, .event-website button')].map(element => {
        const style = getComputedStyle(element);
        return { label: element.textContent.trim(), color: style.color, background: style.backgroundColor };
      })
    JS
    expect(controls).not_to be_empty
    controls.each do |control|
      luminances = %w[color background].map do |key|
        rgb = control.fetch(key).match(/\Argb\((\d+),\s*(\d+),\s*(\d+)\)\z/)
        expect(rgb).not_to be_nil, "#{control.fetch('label')} #{key}: #{control.fetch(key)}"
        channels = rgb.captures.map do |channel|
          value = channel.to_i / 255.0
          value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
        end
        channels.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |value, weight| value * weight }
      end
      bright, dark = luminances.sort.reverse
      expect((bright + 0.05) / (dark + 0.05)).to be >= 4.5
    end
  end

  def expect_keyboard_skip_navigation
    skip = find("a[href='#website-content'],a[href='#event-content']", visible: :all)
    target = page.evaluate_script("arguments[0].getAttribute('href')", skip)
    text = skip.text(:all).strip
    page.execute_script("document.activeElement.blur(); window.scrollTo(0, 0)")
    page.driver.browser.keyboard.type(:Tab)
    expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq(text)
    expect(page.evaluate_script("document.activeElement.getAttribute('href')")).to eq(target)
    page.driver.browser.keyboard.type(:Enter)
    expect(page.evaluate_script("document.activeElement.id")).to eq(target.delete_prefix("#"))
  end

  it "edits, previews, publishes, and restores a real tenant website across mobile and desktop" do
    organization = Organization.create!(name: "Synthetic Browser Community", slug: "website-browser")
    owner = create(:user_for_free_pilot, name: "Synthetic Website Owner")
    Membership.create!(organization:, user: owner, role: :owner)
    event = organization.events.create!(title: "Synthetic Browser Conference", slug: "conference", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now)
    pass = create(:ticket_type, event_id: event.id, price_paise: 0, hidden: true, active: false, capacity: 5, free_published_at: Time.current)
    other_organization = Organization.create!(name: "Synthetic Foreign Community", slug: "website-foreign-browser")
    other_event = other_organization.events.create!(title: "Another Attendee Private Conference", slug: "private", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now)
    other_user = create(:user_for_free_pilot)
    other_pass = create(:ticket_type, event_id: other_event.id, price_paise: 0, hidden: true, active: false, capacity: 5, free_published_at: Time.current)
    other_order = create(:order, :paid, event_id: other_event.id, user_id: other_user.id, total_paise: 0)
    create(:ticket, order: other_order, ticket_type: other_pass, event_id: other_event.id, price_paise: 0)
    sign_in_verified(owner)
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    page.driver.browser.resize(width: 390, height: 844)
    visit organizer_organization_event_path(organization, event)
    click_link "Website"
    expect(page).to have_content("Event website")
    [ [ 320, 740 ], [ 390, 844 ], [ 1400, 1000 ] ].each do |width, height|
      page.driver.browser.resize(width:, height:)
      expect_no_horizontal_overflow
    end
    page.driver.browser.resize(width: 390, height: 844)
    expect_keyboard_skip_navigation
    select "Campus", from: "Theme"
    fill_in "Summary", with: "First browser publication"
    fill_in "About", with: "Synthetic community-built conference website."
    fill_in "Venue name", with: "Synthetic Community Hall"
    find("summary", text: /Programme/i).click
    fill_in "website_programme_0_time", with: "09:00"
    fill_in "website_programme_0_title", with: "Synthetic Tenant Talk"
    fill_in "website_programme_0_speaker", with: "Synthetic Tenant Speaker"
    find("summary", text: /Sponsors/i).click
    fill_in "website_sponsors_0_name", with: "Synthetic Tenant Sponsor"
    fill_in "website_sponsors_0_tier", with: "Community"
    click_button "Save draft"
    expect(page).to have_content("Draft saved. Your public website is unchanged.")
    setting = EventWebsiteSetting.find_by!(event:)
    expect(setting.draft.fetch("summary")).to eq("First browser publication")
    expect(setting.published).to be_nil
    click_link "Preview saved draft"
    expect(page).to have_content(event.title)
    [ "First browser publication", "Synthetic Tenant Talk", "Synthetic Tenant Sponsor" ].each { |text| expect(page).to have_content(text) }
    expect(page).to have_no_css("form[action='#{free_event_registration_path(organization.slug, event.slug)}']")
    expect(Order.where(event_id: event.id)).to be_empty
    expect_no_horizontal_overflow
    expect_registration_contrast
    page.save_screenshot(Rails.root.join("tmp/event-website-preview-390.png"), full: true)
    visit published_event_path(organization.slug, event.slug)
    expect(page).to have_no_content("First browser publication")
    visit organizer_organization_event_website_path(organization, event)
    check "Publish the saved draft"
    click_button "Publish website"
    expect(page).to have_content("Website published for this event.")
    expect(setting.reload.published.fetch("summary")).to eq("First browser publication")
    visit published_event_path(organization.slug, event.slug)
    [ event.title, "First browser publication", "Synthetic Tenant Talk", "Synthetic Tenant Sponsor" ].each { |text| expect(page).to have_content(text) }
    click_button "Register free"
    expect(page).to have_content("You’re registered")
    registered = Order.find_by!(event_id: event.id, user_id: owner.id)
    expect(registered).to have_attributes(total_paise: 0, status: "paid")
    expect(registered.tickets.first).to have_attributes(ticket_type_id: pass.id, event_id: event.id)
    expect(Invoice.count).to eq(0)
    expect(PaymentEvent.count).to eq(0)
    expect(enqueued_jobs).to be_empty
    click_link "Your free tickets"
    expect(page).to have_current_path(free_tickets_path)
    expect(page).to have_link(event.title)
    expect(page).to have_no_content(other_event.title)
    click_link event.title
    expect(page).to have_content("You’re registered")
    visit published_event_path(organization.slug, event.slug)
    [ [ 320, 740 ], [ 390, 844 ], [ 1400, 1000 ] ].each do |width, height|
      page.driver.browser.resize(width:, height:)
      expect_no_horizontal_overflow
      expect_registration_contrast
      page.save_screenshot(Rails.root.join("tmp/event-website-public-#{width}.png"), full: true)
    end
    visit organizer_organization_event_website_path(organization, event)
    fill_in "Summary", with: "Second browser publication"
    click_button "Save draft"
    expect(page).to have_content("Draft saved. Your public website is unchanged.")
    check "Publish the saved draft"
    click_button "Publish website"
    expect(page).to have_content("Website published for this event.")
    visit published_event_path(organization.slug, event.slug)
    expect(page).to have_content("Second browser publication")
    expect(page).to have_no_content("First browser publication")
    visit organizer_organization_event_website_path(organization, event)
    check "Restore the previous publication"
    click_button "Restore previous publication"
    expect(page).to have_content("Previous publication restored. Your saved draft is unchanged.")
    expect(setting.reload.draft.fetch("summary")).to eq("Second browser publication")
    visit published_event_path(organization.slug, event.slug)
    expect(page).to have_content("First browser publication")
    expect(page).to have_no_content("Second browser publication")
  end

  it "keeps actual registration control contrast accessible for all themes and extreme palettes" do
    organization = Organization.create!(name: "Synthetic Contrast Community", slug: "website-contrast")
    owner = create(:user_for_free_pilot)
    Membership.create!(organization:, user: owner, role: :owner)
    event = organization.events.create!(title: "Synthetic Contrast Event", slug: "contrast")
    sign_in_verified(owner)
    visit free_tickets_path
    expect(page).to have_current_path(free_tickets_path)
    expect(page).to have_content("Your free tickets")
    expect(page).to have_no_link(event.title)
    [
      [ "Conference", "#803c35", "#f5f0e7" ],
      [ "Marathon", "#d8f250", "#142c27" ],
      [ "Campus", "#754424", "#f7eecf" ],
      [ "Campus", "#000000", "#ffffff" ],
      [ "Campus", "#ffffff", "#000000" ],
      [ "Conference", "#777777", "#777777" ]
    ].each do |theme, accent, surface|
      visit organizer_organization_event_website_path(organization, event)
      select theme, from: "Theme"
      fill_in "Accent color", with: accent
      fill_in "Surface color", with: surface
      click_button "Save draft"
      expect(page).to have_content("Draft saved. Your public website is unchanged.")
      click_link "Preview saved draft"
      expect(page).to have_content(event.title)
      expect_registration_contrast
    end
  end

  it "lets a viewer inspect defaults and preview without exposing save or publication controls" do
    organization = Organization.create!(name: "Synthetic Viewer Community", slug: "website-viewer")
    viewer = create(:user_for_free_pilot)
    Membership.create!(organization:, user: viewer, role: :viewer)
    event = organization.events.create!(title: "Synthetic Viewer Draft", slug: "draft")
    sign_in_verified(viewer)
    page.driver.browser.resize(width: 320, height: 740)
    visit organizer_organization_event_website_path(organization, event)
    expect(page).to have_content("Event website")
    expect(page).to have_no_button("Save draft")
    expect(page).to have_no_button("Publish website")
    expect_no_horizontal_overflow
    click_link "Preview saved draft"
    expect(page).to have_content(event.title)
    expect_no_horizontal_overflow
    expect(EventWebsiteSetting.count).to eq(0)
  end
end
