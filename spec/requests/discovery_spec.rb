require "rails_helper"

RSpec.describe "External event discovery", type: :request do
  before do
    allow(Rails.configuration.x).to receive(:event_discovery_enabled).and_return(true)
    import_discovery
    import_discovery(source_key: "react", records: [ discovery_record(external_id: "react-one", canonical_url: "https://example.com/react", title: "React in London", city: "London", country_code: "GB", topics: [ "react" ]) ])
  end

  it "is default-off for public HTML, detail and API" do
    allow(Rails.configuration.x).to receive(:event_discovery_enabled).and_return(false)
    [ discovery_listings_path, discovery_listing_path(Discovery::Listing.first), public_discovery_events_path ].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
  end

  it "serves the same filtered factual catalog through HTML and a separate public API" do
    get discovery_listings_path, params: { region: "pune", topic: "ruby", q: "community" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ruby community gathering")
    expect(response.body).not_to include("React in London")
    get public_discovery_events_path, params: { region: "pune", topic: "ruby", q: "community" }
    data = response.parsed_body
    expect(data).to include("total" => 1, "ownership" => "external_discovery", "local_rsvp_enabled" => false)
    expect(data["events"].first).to include("id" => a_string_starting_with("discovery-"), "title" => "Ruby community gathering", "local_rsvp_enabled" => false)
    expect(data["events"].first.keys).not_to include("organization_id", "user_id", "attendees")
  end

  it "separates archive, uncertain dates, review holds and cancellations from upcoming" do
    records = [
      discovery_record(external_id: "past", canonical_url: "https://example.com/past", title: "Past only", starts_on: 1.year.ago.to_date.iso8601),
      discovery_record(external_id: "year", canonical_url: "https://example.com/year", title: "Year uncertain", starts_on: nil, date_precision: "year", date_year: 2027),
      discovery_record(external_id: "hold", canonical_url: "https://example.com/hold", title: "Contradictory dates", review_state: "hold"),
      discovery_record(external_id: "canceled", canonical_url: "https://example.com/canceled", title: "Canceled future", status: "canceled")
    ]
    import_discovery(source_key: "states", records: records)
    get public_discovery_events_path
    expect(response.parsed_body["events"].pluck("title")).not_to include("Past only", "Year uncertain", "Contradictory dates", "Canceled future")
    get public_discovery_events_path, params: { period: "past" }
    expect(response.parsed_body["events"].pluck("title")).to eq([ "Past only" ])
    get public_discovery_events_path, params: { period: "uncertain" }
    expect(response.parsed_body["events"].pluck("title")).to contain_exactly("Year uncertain", "Contradictory dates")
  end

  it "escapes factual titles and exposes only original outbound registration" do
    import_discovery(records: [ discovery_record(title: "<script>alert(1)</script>", registration_url: "https://example.com/register") ])
    get discovery_listing_path(Discovery::Listing.find_by!(canonical_url: "https://example.com/events/one"))
    expect(response.body).to include("&lt;script&gt;", "https://example.com/register", "DQOR does not organize this event")
    expect(response.body).not_to include("<script>alert", "Register free", "csrf-token" + "secret")
  end

  it "cannot create listings, hosted events or memberships through public discovery routes" do
    expect { post discovery_listings_path, params: { organization_id: 1, event: { title: "Forged" } } }.not_to change(Event, :count)
    expect(response).to have_http_status(:not_found)
    expect(Membership.count).to eq(0)
  end

  it "treats search metacharacters as literal text and bounds API pages" do
    get public_discovery_events_path, params: { q: "%", page: -100 }
    expect(response.parsed_body).to include("total" => 0, "page" => 1, "per_page" => 24)
  end
  it "filters the India weekend without inventing intervening occurrence days" do
    travel_to Time.utc(2026, 10, 16, 12) do
      import_discovery(source_key: "weekend", records: [
        discovery_record(external_id: "sat", canonical_url: "https://example.com/saturday", title: "Saturday gathering", starts_on: "2026-10-17"),
        discovery_record(external_id: "range", canonical_url: "https://example.com/ongoing", title: "Ongoing weekend gathering", starts_on: "2026-10-16", ends_on: "2026-10-18"),
        discovery_record(external_id: "gap", canonical_url: "https://example.com/separate-days", title: "Friday and Monday only", starts_on: "2026-10-16", ends_on: "2026-10-19", occurrence_dates: [ "2026-10-16", "2026-10-19" ]),
        discovery_record(external_id: "held", canonical_url: "https://example.com/held", title: "Held dates", starts_on: "2026-10-17", review_state: "hold"),
        discovery_record(external_id: "canceled-weekend", canonical_url: "https://example.com/canceled-weekend", title: "Canceled Saturday", starts_on: "2026-10-17", status: "canceled")
      ])
      get public_discovery_events_path, params: { period: "weekend", region: "pune" }
      expect(response.parsed_body["events"].pluck("title")).to eq([ "Ongoing weekend gathering", "Saturday gathering" ])
    end
  end

  it "paginates deterministically and retains catalog filters" do
    records = 26.times.map { |i| discovery_record(external_id: "page-#{i}", canonical_url: "https://example.com/page-#{i}", title: "Numbered event #{i.to_s.rjust(2, '0')}") }
    import_discovery(source_key: "pages", records: records)
    get public_discovery_events_path, params: { q: "Numbered", page: 1 }
    first = response.parsed_body
    get public_discovery_events_path, params: { q: "Numbered", page: 2 }
    second = response.parsed_body
    expect(first).to include("total" => 26, "page" => 1)
    expect(first["events"].size).to eq(24)
    expect(second["events"].size).to eq(2)
    expect(first["events"].pluck("id") & second["events"].pluck("id")).to be_empty
    get discovery_listings_path, params: { q: "Numbered", region: "pune", view: "cards" }
    expect(response.body).to include("page=2", "region=pune", "view=cards")
  end

  it "shows source-published end times without fabricating missing ones" do
    import_discovery(records: [ discovery_record(date_precision: "time", starts_on: "2026-11-01", starts_at: "2026-11-01T09:00:00+05:30", ends_at: "2026-11-01T17:00:00+05:30") ])
    get discovery_listing_path(Discovery::Listing.find_by!(canonical_url: "https://example.com/events/one"))
    expect(response.body).to include("9:00 AM – 5:00 PM", "Asia/Kolkata")
  end
  it "withholds unsafe outbound URLs even if storage was modified outside the importer" do
    listing = Discovery::Listing.find_by!(canonical_url: "https://example.com/events/one")
    listing.update_column(:registration_url, "javascript:alert(1)")
    listing.references.first.update_column(:source_url, "javascript:alert(2)")
    get discovery_listing_path(listing)
    expect(response.body).not_to include("javascript:", "View on")
    expect(response.body).to include("Source link unavailable")
    get public_discovery_events_path
    expect(response.parsed_body["events"].find { |event| event["id"] == "discovery-#{listing.id}" }).to include("registration_url" => nil)
    expect(response.body).not_to include("javascript:")
  end
end
