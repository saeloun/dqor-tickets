require "rails_helper"

RSpec.describe "Talk bookmarks", type: :request do
  def sign_in_as(user)
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  let(:talk) { Talk.create!(title: "Keynote", published: true) }

  it "requires sign-in" do
    post talk_bookmark_path(talk)

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "saves and removes a talk from the personal schedule" do
    user = User.create!(email: "grace@example.com")
    sign_in_as(user)

    expect { post talk_bookmark_path(talk) }.to change { user.talk_bookmarks.count }.by(1)
    expect(user.bookmarked?(talk)).to be(true)

    expect { delete talk_bookmark_path(talk) }.to change { user.talk_bookmarks.count }.by(-1)
  end
end
