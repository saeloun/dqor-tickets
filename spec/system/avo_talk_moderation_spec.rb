require "rails_helper"

RSpec.describe "Avo talk moderation", type: :system do
  it "renders both existing resources and author names in the authenticated browser" do
    admin = create(:admin_user, password: "password123")
    author = User.create!(name: "Synthetic Author", email: "synthetic-author@example.com")
    talk = Talk.create!(title: "Synthetic moderation talk", published: true)
    question = TalkQuestion.create!(talk: talk, user: author, body: "Synthetic audience question")
    feedback = TalkFeedback.create!(talk: talk, user: author, rating: 5, comment: "Synthetic audience feedback")
    before = [ question.attributes, feedback.attributes, author.attributes ]

    visit new_session_path
    fill_in "email", with: admin.email
    fill_in "password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path("/avo/dashboard")
    { "talk_questions" => question, "talk_feedbacks" => feedback }.each do |resource, record|
      visit "/avo/resources/#{resource}"
      expect(page).to have_content(author.name)
      expect(page).to have_content(talk.title)
      page.save_screenshot("avo-#{resource}-index.png")
      visit "/avo/resources/#{resource}/#{record.id}"
      expect(page).to have_content(author.name)
      expect(page).to have_content(record.is_a?(TalkQuestion) ? record.body : record.comment)
      expect(page).to have_link(talk.title)
      click_link talk.title, match: :first
      expect(page).to have_current_path("/avo/resources/talks/#{talk.id}", ignore_query: true)
      expect(page).to have_content(talk.title)
    end
    expect([ question.reload.attributes, feedback.reload.attributes, author.reload.attributes ]).to eq(before)
  end
end
