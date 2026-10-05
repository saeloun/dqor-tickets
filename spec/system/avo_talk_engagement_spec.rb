require "rails_helper"

RSpec.describe "Avo talk engagement review", type: :system do
  it "lets an admin review feedback and audience questions in the mounted resources" do
    admin = create(:admin_user, password: "password123")
    talk = Talk.create!(title: "Synthetic browser review", published: true)
    user = User.create!(email: "synthetic-browser-review@example.com", name: "Synthetic reviewer")
    feedback = TalkFeedback.create!(talk:, user:, rating: 4, comment: "Synthetic browser feedback")
    question = TalkQuestion.create!(talk:, user:, body: "Synthetic browser question?")

    visit new_session_path
    fill_in "email", with: admin.email
    fill_in "password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path("/avo/dashboard")

    visit "/avo/resources/talk_feedbacks"
    expect(page).to have_content(talk.title)
    expect(page).to have_content(user.email)
    visit "/avo/resources/talk_feedbacks/#{feedback.id}"
    expect(page).to have_content(feedback.comment)
    expect(page).to have_content(user.email)

    visit "/avo/resources/talk_questions"
    expect(page).to have_content(user.name)
    visit "/avo/resources/talk_questions/#{question.id}"
    expect(page).to have_content(question.body)
    expect(page).to have_content(user.name)
    page.save_screenshot(Rails.root.join("tmp/capybara/avo-talk-engagement-review.png"))
  end
end
