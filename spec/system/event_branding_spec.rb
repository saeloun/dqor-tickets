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
    click_button "Save draft"
    expect(page).to have_content("Draft saved to the server")
    expect(EventBrandingSetting.current.draft.fetch("theme")).to eq("campus")
    click_link "Open saved draft"
    expect(page).to have_content("Saved draft")
    expect(page).to have_content("Deccan Queen on Rails")
    expect(page).to have_css('body[data-theme="campus"]')
    expect(page.evaluate_script("document.querySelector('#brand-logo').naturalWidth")).to eq(32)
    click_link "Back to saved branding"
    check "confirmed"
    click_button "Publish saved configuration"
    expect(page).to have_content("Configuration published. Public activation remains off")
    select "The Movement — energetic", from: "Theme direction"
    click_button "Save draft"
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
    click_button "Save draft"
    expect(page).to have_css('[role="alert"]', text: "Include each supported section exactly once")
    expect(EventBrandingSetting.current.draft.fetch("sections")).to eq(%w[about programme visit])
    expect(page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")).to be(true)
  end
end
