require "rails_helper"

RSpec.describe "Speakers", type: :request do
  it "shows announced speakers and hides drafts, unpublished, and non-announced" do
    Speaker.create!(name: "Ada Lovelace", title: "The first programmer", published: true, status: :announced)
    Speaker.create!(name: "Draft Speaker Person", published: false)
    Speaker.create!(name: "Pending Yet Public Person", published: true, status: :pending)
    Speaker.create!(name: "Announced Unpublished Person", published: false, status: :announced)

    get speakers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ada Lovelace")
    expect(response.body).not_to include("Draft Speaker Person")
    expect(response.body).not_to include("Pending Yet Public Person")
    expect(response.body).not_to include("Announced Unpublished Person")
  end

  it "renders an empty state when none are announced" do
    get speakers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("coming soon")
  end

  it "shows an announced speaker profile with their talks" do
    speaker = Speaker.create!(name: "Ada Lovelace", title: "Programmer", bio: "The first programmer.", published: true, status: :announced)
    Talk.create!(title: "Analytical Engines", speaker: speaker, published: true)

    get speaker_path(speaker)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ada Lovelace")
    expect(response.body).to include("Analytical Engines")
  end

  it "does not expose a non-announced speaker's profile" do
    hidden = Speaker.create!(name: "Pending Person", published: true, status: :pending)

    get speaker_path(hidden)

    expect(response).to have_http_status(:not_found)
  end

  describe "social profile URLs" do
    [ "@ada", "javascript:alert(1)", "//evil.example/ada", "https://evil.example/ada" ].each do |handle|
      it "keeps #{handle.inspect} on fixed social origins consistently on index and detail" do
        speaker = Speaker.create!(name: "Ada Lovelace", published: true, status: :announced, twitter: handle, github: handle)
        rendered_links = [ speakers_path, speaker_path(speaker) ].map do |path|
          get path
          expect(response).to have_http_status(:ok)
          links = response.parsed_body.css(".speaker-card__links a")
          expect(links.map(&:text)).to eq([ "Twitter/X", "GitHub" ])
          expect(links.map { |link| URI.parse(link["href"]).host }).to eq([ "twitter.com", "github.com" ])
          links.each do |link|
            expect(link["target"]).to eq("_blank")
            expect(link["rel"]).to eq("noopener")
          end
          links.map { |link| link["href"] }
        end

        expect(rendered_links.first).to eq([ speaker.twitter_url, speaker.github_url ])
        expect(rendered_links.last).to eq(rendered_links.first)
      end
    end

    [ nil, "", "bad handle", "ada\nprofile", 'ada" onclick="alert(1)' ].each do |handle|
      it "omits blank or malformed #{handle.inspect} on both index and detail" do
        speaker = Speaker.create!(name: "Ada Lovelace", published: true, status: :announced, twitter: handle, github: handle)

        [ speakers_path, speaker_path(speaker) ].each do |path|
          get path
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body.css(".speaker-card__links a")).to be_empty
        end
      end
    end
  end
end
