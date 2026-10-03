require "rails_helper"

RSpec.describe "Community", type: :system do
  def sign_in_as(user)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    visit account_magic_path(token: token)
  end

  it "browses attendees and connects with one" do
    me = User.create!(email: "me@example.com", name: "Me", discoverable: true)
    User.create!(email: "ada@example.com", name: "Ada Lovelace", discoverable: true)
    sign_in_as(me)

    visit community_path
    expect(page).to have_content("Ada Lovelace")

    click_on "Ada Lovelace"
    expect(page).to have_content("Ada Lovelace")

    click_on "Connect"
    expect(page).to have_content(/connected/i)
  end

  it "keeps private profiles out of sharing and discovery" do
    hidden = User.create!(email: "hidden@example.com", name: "Hidden Attendee", discoverable: false)
    sign_in_as(hidden)
    expect(page).to have_content("Your profile is private")
    expect(page).not_to have_field("Shareable profile link")

    me = User.create!(email: "me@example.com", name: "Me")
    sign_in_as(me)
    visit community_path
    expect(page).not_to have_content("Hidden Attendee")
  end
end
