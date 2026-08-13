require "rails_helper"

RSpec.describe "Google Wallet pass", type: :request do
  def confirmed_ticket
    order = create(:order, :paid)
    create(:ticket, order:, attendee_name: "Ana", attendee_email: "ana@example.com", assigned_at: Time.current, tshirt_size: "M")
  end

  it "returns 404 when Google Wallet is not configured" do
    get google_wallet_pass_path(confirmed_ticket.secret)

    expect(response).to have_http_status(:not_found)
  end

  context "when configured" do
    before do
      allow(GoogleWalletGenerator).to receive(:configured?).and_return(true)
      allow_any_instance_of(GoogleWalletGenerator).to receive(:save_url).and_return("https://pay.google.com/gp/v/save/TOKEN")
    end

    it "redirects to the Google Wallet save URL" do
      get google_wallet_pass_path(confirmed_ticket.secret)

      expect(response).to redirect_to("https://pay.google.com/gp/v/save/TOKEN")
    end

    it "returns 404 for an unknown ticket secret" do
      get google_wallet_pass_path("does-not-exist")

      expect(response).to have_http_status(:not_found)
    end
  end
end
