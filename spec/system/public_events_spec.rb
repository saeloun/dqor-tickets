require "rails_helper"

RSpec.describe "Published owned event browser contract", type: :system do
  let!(:organization) { Organization.create!(name: "Synthetic hosts", slug: "synthetic-hosts") }
  let!(:event) { organization.events.create!(title: "Synthetic owned meetup", slug: "meetup", status: :published, starts_at: Time.utc(2026, 11, 7, 12), ends_at: Time.utc(2026, 11, 7, 13), timezone: "Asia/Kolkata") }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:public_events_enabled).and_return(true)
  end

  def read_public_contract(path)
    page.evaluate_async_script(<<~JS, path)
      const done = arguments[arguments.length - 1];
      fetch(arguments[0], { credentials: 'omit', cache: 'no-store' })
        .then(async response => done({ status: response.status, etag: response.headers.get('ETag'), cache: response.headers.get('Cache-Control'), body: await response.json() }))
        .catch(error => done({ error: error.name }));
    JS
  end

  it "consumes actual owned facts and immediately withdraws a cached detail after unpublication" do
    visit published_event_path(organization.slug, event.slug)
    expect(page).to have_css("h1", text: event.title)
    result = read_public_contract(public_event_path("hosted-event-#{event.id}"))
    expect(result.fetch("status")).to eq(200)
    expect(result.fetch("body").fetch("event")).to include("id" => "hosted-event-#{event.id}", "ownership" => "hosted_event", "timezone" => "Asia/Kolkata", "starts_at" => "2026-11-07T17:30:00+05:30")
    expect(result.fetch("etag")).to be_present
    event.update!(status: :draft)
    result = read_public_contract(public_event_path("hosted-event-#{event.id}"))
    expect(result.fetch("status")).to eq(404)
    expect(result.fetch("cache")).to eq("no-store")
    expect(result.fetch("etag")).to be_nil
    expect(result.fetch("body").fetch("error").fetch("code")).to eq("event_not_found")
    expect(read_public_contract(public_events_path).fetch("body").fetch("events")).to eq([])
  end

  it "keeps published events unavailable to the browser when the contract gate is off" do
    visit published_event_path(organization.slug, event.slug)
    expect(page).to have_css("h1", text: event.title)
    allow(Rails.configuration.x).to receive(:public_events_enabled).and_return(false)
    result = read_public_contract(public_event_path("hosted-event-#{event.id}"))
    expect(result.fetch("status")).to eq(404)
    expect(result.fetch("cache")).to eq("no-store")
    expect(result.fetch("body")).not_to have_key("event")
  end
end
