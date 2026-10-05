require "rails_helper"

RSpec.describe "Avo talk engagement", type: :request do
  let(:talk) { Talk.create!(title: "Synthetic feedback session", published: true) }
  let(:user) { User.create!(email: "synthetic-engagement@example.com", name: "Synthetic attendee") }
  let!(:feedback) { TalkFeedback.create!(talk:, user:, rating: 5, comment: "Synthetic feedback for review") }
  let!(:question) { TalkQuestion.create!(talk:, user:, body: "Synthetic audience question?") }

  it "lists and shows feedback through the mounted admin resource" do
    sign_in_admin
    get "/avo/resources/talk_feedbacks"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(talk.title, user.name, user.email)

    get "/avo/resources/talk_feedbacks/#{feedback.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(feedback.comment, user.name, user.email)
  end

  it "lists and shows questions through the mounted admin resource" do
    sign_in_admin
    get "/avo/resources/talk_questions"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(talk.title, user.name, user.email)

    get "/avo/resources/talk_questions/#{question.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(question.body, user.name, user.email)
  end

  it "keeps both resources behind the existing admin authentication" do
    %w[talk_feedbacks talk_questions].each do |resource|
      get "/avo/resources/#{resource}"
      expect(response).to redirect_to("/session/new")
    end
  end

  it "keeps desk staff within the existing check-in scope" do
    sign_in_admin(create(:admin_user, role: :desk, password: "password123"))
    %w[talk_feedbacks talk_questions].each do |resource|
      get "/avo/resources/#{resource}"
      expect(response).to redirect_to("/checkin")
    end
  end
end
