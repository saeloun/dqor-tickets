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

  describe "profile URL safeguards" do
    let(:viewer) { User.create!(email: "viewer@example.com") }
    let(:attendee) { User.create!(email: "profile@example.com", name: "Ada", discoverable: true) }

    before { sign_in_as(viewer) }

    [ "http://ada.dev/about", "https://ada.dev/about?topic=rails#talks", "ada.dev" ].each do |url|
      it "renders a valid normalized website for #{url}" do
        attendee.update!(website: url)
        get attendee_path(attendee)

        link = response.parsed_body.at_css(".attendee-profile__website a")
        expect(link["href"]).to eq(attendee.reload.website)
        expect(link["target"]).to eq("_blank")
        expect(link["rel"]).to eq("noopener")
        expect(link["aria-label"]).to eq("Website for Ada")
      end
    end

    [
      nil, "", "javascript:alert(1)", "javascript://example.com/%0Aalert(1)", "data:text/html,<script>alert(1)</script>",
      "ftp://ada.dev", "//ada.dev", "/profile", "https:profile", "https:///profile",
      "https://", "https://ada.dev/\nprofile", "https://exa mple.test"
    ].each do |url|
      it "omits a legacy stored website #{url.inspect} without falling back to the current page" do
        User.connection.execute("UPDATE users SET website = #{User.connection.quote(url)} WHERE id = #{attendee.id}")
        expect(attendee.reload.website).to eq(url)

        get attendee_path(attendee)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.at_css(".attendee-profile__website")).to be_nil
        expect(response.parsed_body.css(".account-identity a")).to be_empty
      end
    end

    it "omits an invalid Mastodon link while retaining other social profiles and their attributes" do
      attendee.update!(mastodon: "https://", github: "ada")
      get attendee_path(attendee)

      links = response.parsed_body.css(".attendee-profile__links a")
      expect(links.map(&:text)).to eq([ "GitHub" ])
      expect(links.first["href"]).to eq("https://github.com/ada")
      expect(links.first["target"]).to eq("_blank")
      expect(links.first["rel"]).to eq("noopener")
      expect(links.first["aria-label"]).to eq("GitHub profile for Ada")
    end
  end
end
