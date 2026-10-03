require "rails_helper"

RSpec.describe "Mobile organizer operations", type: :system do
  it "records a sponsor installment and completes a giveaway at phone width" do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:organizer_operations_enabled).and_return(true)
    organization = Organization.create!(name: "Demo", slug: "mobile-ops")
    event = organization.events.create!(title: "Demo event", slug: "demo")
    user = User.create!(email: "mobile-ops@example.com")
    Membership.create!(organization: organization, user: user, role: :owner)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    page.driver.resize(390, 844)
    visit account_magic_path(token: token)
    visit organizer_organization_event_path(organization, event)
    click_link "Sponsor and vendor operations"
    fill_in "Contact name", with: "Demo partner"
    click_button "Add contact"
    within('form[action$="/deals"]') do
      fill_in "Title", with: "Gold sponsor"
      fill_in "Amount / estimated in-kind value (integer paise)", with: "10000"
      click_button "Add sponsor deal"
    end
    click_button "Commit Gold sponsor"
    within('form[action$="/entries"]') do
      select "Gold sponsor", from: "Cash sponsor"
      fill_in "Amount (integer paise)", with: "2500"
      fill_in "Date", with: "2026-10-02"
      fill_in "Manual reference", with: "Demo receipt"
      click_button "Record cash movement"
    end
    expect(page).to have_content("Net cash received: 2500 paise")
    within('form[action$="/tasks"]') do
      fill_in "Deliverable / giveaway", with: "Demo giveaway"
      click_button "Add deliverable"
    end
    click_button "Complete Demo giveaway"
    expect(page).to have_content("Demo giveaway · Gold sponsor · Due unscheduled · Completed")
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/capybara/operations-mobile.png"))
  end
end
