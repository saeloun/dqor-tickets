require "rails_helper"

RSpec.describe "Social layer" do
  let(:event) { create(:event) }
  let(:user) { create(:user) }

  it "lets a user post, comment and react in an event feed" do
    post = event.posts.create!(user:, body: "Hello RubyConf!")
    comment = post.comments.create!(user:, body: "Excited!")
    reaction = post.reactions.create!(user:, kind: "like")

    expect(event.posts).to include(post)
    expect(post.comments).to include(comment)
    expect(post.reactions).to include(reaction)
    expect(user.posts).to include(post)
  end

  it "prevents duplicate reactions of the same kind but allows different kinds" do
    post = event.posts.create!(user:, body: "Hi")
    post.reactions.create!(user:, kind: "like")

    expect(post.reactions.new(user:, kind: "like")).not_to be_valid
    expect(post.reactions.new(user:, kind: "celebrate")).to be_valid
  end

  it "lets a user follow an organizer only once" do
    organizer = event.organizer
    Follow.create!(user:, followable: organizer)

    expect(Follow.new(user:, followable: organizer)).not_to be_valid
  end

  it "orders posts pinned-first then most recent" do
    event.posts.create!(user:, body: "old", created_at: 2.days.ago)
    pinned = event.posts.create!(user:, body: "pinned", pinned: true, created_at: 3.days.ago)

    expect(event.posts.pinned_first.first).to eq(pinned)
  end

  it "files a moderation report against content" do
    post = event.posts.create!(user:, body: "spam")

    report = Report.create!(reporter: user, reportable: post, reason: "spam")

    expect(report).to be_open
    expect(report.reportable).to eq(post)
  end
end
