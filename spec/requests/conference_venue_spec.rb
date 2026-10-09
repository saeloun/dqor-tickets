require "rails_helper"

RSpec.describe "Conference venue", type: :request do
  [ [ "/", ".hero-content" ], [ "/schedule", ".page-hero" ], [ "/tickets", ".storefront-hero" ] ].each do |path, header|
    it "puts the complete conference address and directions in the #{path} header" do
      get path

      expect(response).to have_http_status(:ok)
      block = response.parsed_body.at_css("#{header} .conference-venue")
      expect(block).not_to be_nil
      expect(block["aria-label"]).to eq("Conference venue")
      expect(block.text).to include("Conference · October 8–9, 2026", "Hyatt Regency Pune & Residences", "Weikfield IT Park, Nagar Road, Pune 411014, Maharashtra, India")
      destination = "Hyatt Regency Pune & Residences, Weikfield IT Park, Nagar Road, Pune 411014, Maharashtra, India"
      google = URI(block.at_css('a[data-map="google"]')["href"])
      apple = URI(block.at_css('a[data-map="apple"]')["href"])
      expect([ google.scheme, google.host, google.path ]).to eq([ "https", "www.google.com", "/maps/dir/" ])
      expect(URI.decode_www_form(google.query).to_h).to eq("api" => "1", "destination" => destination)
      expect([ apple.scheme, apple.host, apple.path ]).to eq([ "https", "maps.apple.com", "/directions" ])
      expect(URI.decode_www_form(apple.query).to_h).to eq("destination" => destination, "mode" => "driving")
      expect(block.css("a").map(&:text)).to contain_exactly("Google Maps directions", "Apple Maps directions")
      expect(block.css("a").map { |link| link["rel"].split }).to all(include("noopener", "noreferrer"))
    end
  end

  it "keeps the Rails Girls workshop date and venue distinct from the conference" do
    girls = create(:ticket_type, slug: "rails-girls-pune", description: "Rails Girls workshop at Zendesk Pune", event_starts_on: Date.new(2026, 10, 10), event_ends_on: Date.new(2026, 10, 10))
    before = girls.attributes

    get tickets_store_path

    card = response.parsed_body.at_css("#ticket_type_#{girls.id}")
    expect(card.text).to include("October 10, 2026", "Zendesk Pune")
    expect(card.text).not_to include("Hyatt Regency", "Weikfield IT Park")
    expect(girls.reload.attributes).to eq(before)
  end
end
