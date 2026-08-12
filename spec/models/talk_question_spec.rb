require "rails_helper"

RSpec.describe TalkQuestion do
  let(:talk) { Talk.create!(title: "Talk", published: true) }
  let(:asker) { User.create!(email: "a@example.com", name: "Asker") }

  it "validates body presence and max length" do
    expect(talk.talk_questions.new(user: asker, body: "")).not_to be_valid
    expect(talk.talk_questions.new(user: asker, body: "x" * 501)).not_to be_valid
    expect(talk.talk_questions.new(user: asker, body: "How do you scale?")).to be_valid
  end

  it "orders questions newest first" do
    older = talk.talk_questions.create!(user: asker, body: "older", created_at: 2.minutes.ago)
    newer = talk.talk_questions.create!(user: asker, body: "newer")

    expect(talk.talk_questions.recent.to_a).to eq([ newer, older ])
  end
end
