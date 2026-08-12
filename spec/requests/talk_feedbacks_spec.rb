require "rails_helper"

RSpec.describe "Talk feedback", type: :request do
  def sign_in_as(user)
    get account_magic_path(
      token: Rails.application.message_verifier(:account_magic_link)
        .generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    )
  end

  def attending_user(email)
    user = User.create!(email: email)
    create(:order, :paid, email: email)
    user
  end

  let(:talk) { Talk.create!(title: "Rails at Scale", published: true, starts_at: 2.hours.ago, ends_at: 1.hour.ago) }

  it "requires sign-in" do
    post talk_feedback_path(talk), params: { talk_feedback: { rating: 5 } }

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "refuses feedback from someone without a pass" do
    sign_in_as(User.create!(email: "nopass@example.com"))

    expect { post talk_feedback_path(talk), params: { talk_feedback: { rating: 5 } } }
      .not_to change { TalkFeedback.count }
    expect(response).to redirect_to(schedule_path)
  end

  it "refuses feedback before the talk has finished" do
    future = Talk.create!(title: "Later", published: true, starts_at: 1.hour.from_now)
    sign_in_as(attending_user("early@example.com"))

    expect { post talk_feedback_path(future), params: { talk_feedback: { rating: 5 } } }
      .not_to change { TalkFeedback.count }
  end

  it "records feedback from an attendee after the talk" do
    sign_in_as(attending_user("fan@example.com"))

    expect { post talk_feedback_path(talk), params: { talk_feedback: { rating: 5, comment: "loved it" } } }
      .to change { talk.talk_feedbacks.count }.by(1)
    expect(response).to redirect_to(schedule_path)
  end

  it "updates an existing rating instead of duplicating" do
    sign_in_as(attending_user("again@example.com"))
    post talk_feedback_path(talk), params: { talk_feedback: { rating: 3 } }

    expect { post talk_feedback_path(talk), params: { talk_feedback: { rating: 5 } } }
      .not_to change { TalkFeedback.count }
    expect(talk.talk_feedbacks.first.rating).to eq(5)
  end

  it "shows the rating form to an attendee after a talk ends" do
    talk
    sign_in_as(attending_user("viewer@example.com"))

    get schedule_path

    expect(response.body).to include("star-rating")
    expect(response.body).to include("Submit rating")
  end

  it "shows the happening-now banner on the schedule during the event" do
    allow(Conference).to receive(:status).and_return(:during)
    Talk.create!(title: "Live One", published: true, starts_at: 10.minutes.ago, ends_at: 20.minutes.from_now)

    get schedule_path

    expect(response.body).to include("Happening now")
    expect(response.body).to include("Live One")
  end
end
