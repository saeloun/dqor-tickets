require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "safe_profile_url" do
    [
      "http://example.test",
      "https://example.test/about?topic=rails&sort=new#talks",
      "https://example.test:8443/a%20profile"
    ].each do |url|
      it "preserves the valid URL #{url}" do
        expect(helper.safe_profile_url(url)).to eq(url)
        expect(helper.safe_profile_url(url)).not_to be_html_safe
      end
    end

    [
      nil, "", " ", "javascript:alert(1)", "data:text/html,<script>alert(1)</script>",
      "mailto:ada@example.test", "ftp://example.test", "//example.test/path", "/profile",
      "https:profile", "https:/profile", "https:///profile", "https://",
      "https://exa mple.test", "https://example.test/\nprofile", "https://example.test/<script>",
      "https://[invalid"
    ].each do |url|
      it "rejects the unsafe or malformed URL #{url.inspect}" do
        expect(helper.safe_profile_url(url)).to be_nil
      end
    end
  end

  describe "attendee_social_links" do
    it "omits a malformed Mastodon URL and keeps fixed-origin encoded social handles" do
      user = User.new(email: "ada@example.test", mastodon: "https://", x_username: "javascript:alert(1)", github: "//evil.example/ada")

      links = helper.attendee_social_links(user)

      expect(links.map(&:first)).to eq([ "X", "GitHub" ])
      expect(links.map { |_, url, _| URI.parse(url).host }).to eq([ "x.com", "github.com" ])
      expect(links.map { |_, url, _| url }).to eq([ "https://x.com/javascript%3Aalert%281%29", "https://github.com/%2F%2Fevil.example%2Fada" ])
    end
  end
end
