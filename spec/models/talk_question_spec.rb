require "rails_helper"

RSpec.describe TalkQuestion do
  let(:talk) { Talk.create!(title: "Talk", published: true) }
  let(:asker) { User.create!(email: "a@example.com", name: "Asker") }
  let(:voter) { User.create!(email: "v@example.com", name: "Voter") }

  it "validates body presence and max length" do
    expect(talk.talk_questions.new(user: asker, body: "")).not_to be_valid
    expect(talk.talk_questions.new(user: asker, body: "x" * 501)).not_to be_valid
    expect(talk.talk_questions.new(user: asker, body: "How do you scale?")).to be_valid
  end

  it "ranks by upvotes then age" do
    q1 = talk.talk_questions.create!(user: asker, body: "first")
    q2 = talk.talk_questions.create!(user: asker, body: "second")
    q2.question_upvotes.create!(user: voter)

    expect(talk.talk_questions.ranked.to_a).to eq([ q2, q1 ])
  end

  it "tracks count and per-user upvote state" do
    q = talk.talk_questions.create!(user: asker, body: "q")
    q.question_upvotes.create!(user: voter)

    expect(q.upvotes_count).to eq(1)
    expect(q.upvoted_by?(voter)).to be(true)
    expect(q.upvoted_by?(asker)).to be(false)
  end

  it "allows one upvote per user per question" do
    q = talk.talk_questions.create!(user: asker, body: "q")
    q.question_upvotes.create!(user: voter)

    expect(q.question_upvotes.new(user: voter)).not_to be_valid
  end
end
