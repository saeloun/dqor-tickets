require "rails_helper"

RSpec.describe "Wall of Love Sentry privacy" do
  it "removes both structured and raw request bodies before sending events" do
    configuration = Sentry::Configuration.new
    allow(Sentry).to receive(:init).and_yield(configuration)
    old_dsn = ENV["SENTRY_DSN"]
    ENV["SENTRY_DSN"] = "https://public@example.com/1"
    begin
      load Rails.root.join("config/initializers/sentry.rb")
    ensure
      ENV["SENTRY_DSN"] = old_dsn
    end

    [ { wall_love_note: { public_name: "Private synthetic name", note: "Private synthetic note", source_url: "https://example.com/private" } }, "wall_love_note[note]=Private+synthetic+note" ].each do |body|
      request = Struct.new(:url, :data, :query_string).new("https://example.com/wall-of-love?note=private", body, "note=private")
      event = Struct.new(:request).new(request)
      configuration.before_send.call(event, {})
      expect(event.request.data).to be_nil
      expect(event.request.query_string).to be_nil
      expect(event.request.url).to eq("https://example.com/wall-of-love")
    end
    expect(configuration.send_default_pii).to be(false)
  end
end
