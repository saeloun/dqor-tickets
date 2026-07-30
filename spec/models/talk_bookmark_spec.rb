require "rails_helper"

RSpec.describe TalkBookmark do
  it "prevents duplicate bookmarks for the same user and talk" do
    user = User.create!(email: "a@example.com")
    talk = Talk.create!(title: "Keynote")
    user.talk_bookmarks.create!(talk: talk)

    expect(user.talk_bookmarks.build(talk: talk)).not_to be_valid
  end
end
