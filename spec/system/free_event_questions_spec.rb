require "rails_helper"

RSpec.describe "Registration question journey", type: :system do
  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_questions_enabled).and_return(true)
  end

  def login(user)
    visit account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  it "edits and previews ordered questions, preserves mobile Back/error values and stores one immutable response" do
    owner = create(:user_for_free_pilot, name: "Synthetic Organizer")
    attendee = create(:user_for_free_pilot, name: "Synthetic Attendee")
    org = Organization.create!(name: "Ruby Community", slug: "question-journey")
    Membership.create!(organization: org, user: owner, role: :owner)
    event = org.events.create!(title: "An evening with Ruby", slug: "ruby-evening", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now)
    type = create(:ticket_type, name: "Community admission", event_id: event.id, price_paise: 0, hidden: true, active: false, capacity: 4, free_published_at: Time.current)
    login(owner)
    visit free_event_questions_path(org, event, type)
    within("section.card", text: "Add a question") do
      fill_in "Question", with: "What would you like to learn?"
      fill_in "Helper text (optional)", with: "A topic or idea is enough."
      expect(page).not_to have_field("Choices (choose-one questions only)")
      select "Choose one", from: "Answer type"
      fill_in "Choices (choose-one questions only)", with: "Ruby\nRails"
      select "Long text", from: "Answer type"
      expect(page).not_to have_field("Choices (choose-one questions only)")
      select "Choose one", from: "Answer type"
      expect(page).to have_field("Choices (choose-one questions only)", with: "Ruby\nRails")
      select "Short text", from: "Answer type"
      select "Required", from: "Is an answer required?"
      click_button "Add question"
    end
    expect(page).to have_content("Question draft saved")
    within("section.card", text: "Add a question") do
      fill_in "Question", with: "Anything else?"
      select "Long text", from: "Answer type"
      click_button "Add question"
    end
    click_button "Move question 2 up"
    expect(page.all("article.card h2").first.text).to include("Anything else?")
    click_link "Preview draft"
    expect(page).to have_content("Draft preview")
    expect(page).to have_field("Anything else? (Optional)", disabled: true)
    click_link "Back to questions"
    click_button "Publish questions"
    expect(page).to have_content("Published version 1 · Read only")
    page.save_screenshot(Rails.root.join("tmp/questions-organizer.png"))
    login(attendee)
    visit published_event_path(org.slug, event.slug)
    click_link "Register free"
    page.driver.browser.resize(width: 390, height: 844)
    expect(page).to have_content("Community admission · Free")
    fill_in "Anything else? (Optional)", with: "Looking forward to it"
    fill_in "What would you like to learn? (Required)", with: "Ruby performance"
    click_link "Back to event"
    click_button "Continue registration"
    expect(page).to have_field("What would you like to learn? (Required)", with: "Ruby performance")
    page.go_back
    click_button "Continue registration"
    expect(page).to have_field("Anything else? (Optional)", with: "Looking forward to it")
    fill_in "What would you like to learn? (Required)", with: ""
    page.execute_script("document.querySelector('[data-registration-dialog] form').noValidate = true")
    click_button "Complete registration"
    expect(page).to have_content("This answer is required")
    expect(page).to have_field("Anything else? (Optional)", with: "Looking forward to it")
    page.save_screenshot(Rails.root.join("tmp/questions-attendee-error-mobile.png"))
    fill_in "What would you like to learn? (Required)", with: "Ruby performance"
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    page.save_screenshot(Rails.root.join("tmp/questions-attendee-mobile.png"))
    page.execute_script("document.querySelector('[data-registration-dialog]').scrollTop = 100000")
    expect(page).to have_link("Back to event")
    page.save_screenshot(Rails.root.join("tmp/questions-attendee-action-mobile.png"))
    page.driver.browser.resize(width: 320, height: 740)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth && document.querySelector('[data-registration-dialog]').scrollWidth <= document.querySelector('[data-registration-dialog]').clientWidth")).to be(true)
    page.execute_script("document.querySelector('[data-registration-dialog]').scrollTop = 100000")
    page.save_screenshot(Rails.root.join("tmp/questions-attendee-action-320.png"))
    click_button "Complete registration"
    expect(page).to have_content("You’re registered")
    expect(FreeEvents::Response.sole.answers.values).to include("Ruby performance", "Looking forward to it")
    expect(Invoice.count).to eq(0)
    expect(enqueued_jobs).to be_empty
  end
end
