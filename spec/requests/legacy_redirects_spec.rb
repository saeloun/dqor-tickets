require "rails_helper"

RSpec.describe "Legacy marketing-site URLs", type: :request do
  {
    "/cfp"              => "/#cfp",
    "/cfp/"             => "/#cfp",
    "/venue"            => "/#venue",
    "/rails-girls"      => "/#rails-girls",
    "/explore-pune-day" => "/#explore-pune-day",
    "/contact"          => "/#contact",
    "/waitlist"         => "/#tickets",
    "/thanks"           => "/"
  }.each do |from, to|
    it "permanently redirects #{from} to #{to}" do
      get from

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(to)
    end
  end
end
