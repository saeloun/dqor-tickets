require "rails_helper"

RSpec.describe "Entry pass QR", type: :request do
  it "renders a scannable entry QR on the claim page for an assigned ticket" do
    ticket = create(:ticket, order: create(:order, :paid))

    get ticket_claim_path(ticket.claim_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("entry-pass")
    expect(response.body).to include("<svg")
    expect(response.body).to include(ticket.secret)
  end
  [
    [ "Rails Girls", "2026-10-10", "2026-10-10", "October 10, 2026" ],
    [ "Conference", "2026-10-08", "2026-10-09", "October 8, 2026 – October 9, 2026" ],
    [ "Open ending", "2026-10-08", nil, "From October 8, 2026" ],
    [ "Open start", nil, "2026-10-10", "Through October 10, 2026" ],
    [ "Unspecified", nil, nil, nil ]
  ].each do |name, starts_on, ends_on, label|
    it "shows only stored admission dates for #{name}" do
      type = create(:ticket_type, name: name, event_starts_on: starts_on, event_ends_on: ends_on)
      ticket = create(:ticket, ticket_type: type, order: create(:order, :paid))

      get ticket_claim_path(ticket.claim_token)

      expect(response).to have_http_status(:ok)
      dates = Nokogiri::HTML(response.body).at_css(".entry-pass__date").text.strip
      expect(dates).to eq([ label, "Pune" ].compact.join(" · "))
      expect(type.reload.event_starts_on).to eq(starts_on && Date.parse(starts_on))
      expect(type.event_ends_on).to eq(ends_on && Date.parse(ends_on))
    end
  end
end
