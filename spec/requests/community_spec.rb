require "rails_helper"

RSpec.describe "Community", type: :request do
  def sign_in_as(user)
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  it "requires sign-in" do
    get community_path

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "lists discoverable attendees except yourself" do
    me = User.create!(email: "me@example.com", name: "Zephyr Selftest", discoverable: true)
    User.create!(email: "ada@example.com", name: "Ada Discoverable", discoverable: true)
    User.create!(email: "hidden@example.com", name: "Hidden Person", discoverable: false)
    sign_in_as(me)

    get community_path

    expect(response.body).to include("Ada Discoverable")
    expect(response.body).not_to include("Hidden Person")
    expect(response.body).not_to include("Zephyr Selftest")
  end

  it "shows a discoverable attendee profile with a connect action" do
    me = User.create!(email: "me@example.com")
    ada = User.create!(email: "ada@example.com", name: "Ada", discoverable: true)
    sign_in_as(me)

    get attendee_path(ada)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ada")
    expect(response.body).to include("Connect")
  end

  it "renders filled profile links and hides blank ones" do
    me = User.create!(email: "me@example.com")
    ada = User.create!(
      email: "ada@example.com",
      name: "Ada",
      discoverable: true,
      website: "ada.dev",
      x_username: "ada",
      bluesky: "ada.bsky.social",
      mastodon: "ada@ruby.social",
      linkedin: "ada-lovelace"
    )
    sign_in_as(me)

    get attendee_path(ada)

    expect(response.body).to include('href="https://ada.dev"')
    expect(response.body).to include('href="https://x.com/ada"')
    expect(response.body).to include('href="https://bsky.app/profile/ada.bsky.social"')
    expect(response.body).to include('href="https://ruby.social/@ada"')
    expect(response.body).to include('href="https://www.linkedin.com/in/ada-lovelace"')
    expect(response.body).not_to include("GitHub profile for Ada")

    profile_links = Nokogiri::HTML(response.body).css(".attendee-profile__website a, .attendee-profile__links a")
    expect(profile_links).not_to be_empty
    profile_links.each do |link|
      expect(link["target"]).to eq("_blank")
      expect(link["rel"]).to eq("noopener")
      expect(link["aria-label"]).to be_present
    end
  end

  it "allows a direct profile visit without adding a hidden attendee to the directory" do
    me = User.create!(email: "me@example.com")
    hidden = User.create!(email: "hidden@example.com", name: "Hidden Attendee", discoverable: false)
    sign_in_as(me)

    get community_path
    expect(response.body).not_to include("Hidden Attendee")

    get attendee_path(hidden)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Hidden Attendee")
    expect(response.body).to include("Connect")
  end

  it "strips executable website protocols even if a stored value bypassed validation" do
    me = User.create!(email: "me@example.com")
    attendee = User.create!(email: "unsafe@example.com", website: "https://example.com")
    User.where(id: attendee.id).update_all(website: "javascript://example.com/%0Aalert(1)")
    sign_in_as(me)

    get attendee_path(attendee)

    link = Nokogiri::HTML(response.body).at_css(".attendee-profile__website a")
    expect(link.text).to eq("Website")
    expect(link["href"]).to be_nil
    expect(link["rel"]).to eq("noopener")
    expect(link["aria-label"]).to be_present
  end
end
