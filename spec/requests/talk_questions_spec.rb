require "rails_helper"

RSpec.describe "Talk Q&A", type: :request do
  def sign_in_as(user)
    get account_magic_path(
      token: Rails.application.message_verifier(:account_magic_link)
        .generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    )
  end

  def attending(email)
    user = User.create!(email: email, name: "Fan")
    create(:order, :paid, email: email)
    user
  end

  let(:talk) { Talk.create!(title: "Rails Q&A", published: true, starts_at: 1.hour.ago) }

  it "shows the talk page and its questions publicly" do
    talk.talk_questions.create!(user: User.create!(email: "x@example.com"), body: "How does it work?")

    get talk_path(talk)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Audience questions")
    expect(response.body).to include("How does it work?")
  end

  it "requires sign-in to ask" do
    post talk_questions_path(talk), params: { talk_question: { body: "Question?" } }

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "blocks a non-attendee from asking" do
    sign_in_as(User.create!(email: "nopass@example.com"))

    expect { post talk_questions_path(talk), params: { talk_question: { body: "Question?" } } }
      .not_to change { TalkQuestion.count }
  end

  it "lets an attendee ask a question" do
    sign_in_as(attending("fan@example.com"))

    expect { post talk_questions_path(talk), params: { talk_question: { body: "Where do I start?" } } }
      .to change { talk.talk_questions.count }.by(1)
  end
end
