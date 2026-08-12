require "rails_helper"

RSpec.describe TalkFeedback do
  let(:talk) { Talk.create!(title: "Talk", published: true, starts_at: 2.hours.ago, ends_at: 1.hour.ago) }
  let(:user) { User.create!(email: "a@example.com") }

  it "requires a rating between 1 and 5" do
    expect(talk.talk_feedbacks.new(user: user, rating: 0)).not_to be_valid
    expect(talk.talk_feedbacks.new(user: user, rating: 6)).not_to be_valid
    expect(talk.talk_feedbacks.new(user: user, rating: 4)).to be_valid
  end

  it "is unique per user and talk" do
    talk.talk_feedbacks.create!(user: user, rating: 4)
    expect(talk.talk_feedbacks.new(user: user, rating: 5)).not_to be_valid
  end

  it "computes average and count on the talk" do
    talk.talk_feedbacks.create!(user: user, rating: 5)
    talk.talk_feedbacks.create!(user: User.create!(email: "b@example.com"), rating: 2)

    expect(talk.average_rating).to eq(3.5)
    expect(talk.ratings_count).to eq(2)
  end

  describe "Talk#over?" do
    it "is true after the talk ends and false before it starts" do
      expect(talk.over?).to be(true)
      expect(Talk.create!(title: "Later", published: true, starts_at: 1.hour.from_now).over?).to be(false)
      expect(Talk.create!(title: "TBA", published: true).over?).to be(false)
    end
  end
end
