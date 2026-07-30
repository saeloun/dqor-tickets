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
end
