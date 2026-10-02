require "rails_helper"

RSpec.describe "Organizer branding", type: :system do
  let(:operator) { create(:admin_user, password: "password123") }

  def open_editor
    visit organizer_branding_path
    fill_in "email", with: operator.email
    fill_in "password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path(organizer_branding_path)
  end

  it "saves, previews, publishes and rolls back real server configurations" do
    open_editor
    select "The Commons — editorial", from: "Theme direction"
    select "Modern sans", from: "Heading style"
    attach_file "Logo", Rails.root.join("public/dqor/favicon-32x32.png")
    within("#branding-draft-form") { click_button "Save draft" }
    expect(page).to have_content("Draft saved to the server")
    expect(EventBrandingSetting.current.draft.fetch("theme")).to eq("campus")
    click_link "Open saved draft"
    expect(page).to have_content("Saved draft")
    within_frame(find("#saved-preview-dialog iframe")) do
      expect(page).to have_content("Deccan Queen on Rails")
      expect(page).to have_css('body[data-theme="campus"]')
      expect(page.evaluate_script("document.querySelector('#brand-logo').naturalWidth")).to eq(32)
      click_link "Programme", exact: true
      expect(page.evaluate_script("window.scrollY")).to be > 0
      click_link "Back to saved branding"
    end
    expect(page).not_to have_css("dialog[open]")
    check "confirmed"
    click_button "Publish saved configuration"
    expect(page).to have_content("Configuration published. Public activation remains off")
    select "The Movement — energetic", from: "Theme direction"
    within("#branding-draft-form") { click_button "Save draft" }
    check "confirmed"
    click_button "Publish saved configuration"
    expect(page).to have_content("Configuration published. Public activation remains off")
    check "rollback_confirmed"
    click_button "Restore previous publication"
    expect(page).to have_content("Previous published configuration restored")
    expect(EventBrandingSetting.current.published.fetch("theme")).to eq("campus")
    expect(EventBrandingSetting.current.draft.fetch("theme")).to eq("marathon")
  end

  it "keeps the mobile form usable and presents invalid order errors without saving" do
    page.driver.browser.resize(width: 390, height: 844)
    open_editor
    select "About", from: "Position 2"
    within("#branding-draft-form") { click_button "Save draft" }
    expect(page).to have_css('[role="alert"]', text: "Include each supported section exactly once")
    expect(page).to have_select("Position 2", selected: "About")
    expect(EventBrandingSetting.current.draft.fetch("sections")).to eq(%w[about programme visit])
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
  end
  it "preserves mobile edits through preview, browser Back, Escape and cancelled image selection" do
    page.driver.browser.resize(width: 390, height: 844)
    open_editor
    fill_in "Accent hex", with: "#224466"
    attach_file "Cover", Rails.root.join("public/dqor/favicon-32x32.png")
    expect(page).to have_css('canvas[aria-label="Selected cover preview"]')
    click_link "Saved preview"
    expect(page).to have_css("dialog[open]")
    expect(page.evaluate_script("document.activeElement.id")).to eq("close-preview")
    page.go_back
    expect(page).not_to have_css("dialog[open]")
    expect(page).to have_field("Accent hex", with: "#224466")
    expect(page).to have_css('canvas[aria-label="Selected cover preview"]')
    click_link "Saved preview"
    page.send_keys(:escape)
    expect(page).not_to have_css("dialog[open]")
    expect(page.evaluate_script("document.activeElement.textContent")).to eq("Saved preview")
    click_button "Cancel selection"
    expect(page).not_to have_css('canvas[aria-label="Selected cover preview"]')
    check "confirmed"
    click_button "Publish saved configuration"
    expect(page).to have_content("Save your draft before publishing")
    expect(EventBrandingSetting.current.published).to be_nil
    within("#branding-draft-form") { click_button "Save draft" }
    expect(page).to have_content("Draft saved to the server")
    expect(EventBrandingSetting.current.draft.fetch("accent")).to eq("#224466")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
  end
  it "keeps edits after a failed connection and sends repeated save or publish clicks only once" do
    open_editor
    fill_in "Accent hex", with: "#334455"
    page.execute_script("window.originalFetch = window.fetch; window.fetch = () => Promise.reject(new Error('Connection lost'))")
    within("#branding-draft-form") { click_button "Save draft" }
    expect(page).to have_content("Connection lost")
    expect(page).to have_field("Accent hex", with: "#334455")
    page.execute_script("window.fetch = window.originalFetch")
    revision = EventBrandingSetting.current.lock_version
    page.execute_script("const form = document.querySelector('#branding-draft-form'); form.requestSubmit(); form.requestSubmit()")
    expect(page).to have_content("Draft saved to the server")
    expect(EventBrandingSetting.current.lock_version).to eq(revision + 1)
    check "confirmed"
    page.execute_script("const form = document.querySelector('#confirmed').form; form.requestSubmit(); form.requestSubmit()")
    expect(page).to have_content("Configuration published. Public activation remains off")
    expect(EventBrandingSetting.current.lock_version).to eq(revision + 2)
  end
end
