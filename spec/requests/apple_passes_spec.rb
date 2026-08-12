require "rails_helper"

RSpec.describe "Apple Wallet pass", type: :request do
  def confirmed_ticket
    order = create(:order, :paid)
    create(:ticket, order:, attendee_name: "Ana", attendee_email: "ana@example.com", assigned_at: Time.current, tshirt_size: "M")
  end

  it "returns 404 when Apple Wallet is not configured" do
    get apple_pass_path(confirmed_ticket.secret)

    expect(response).to have_http_status(:not_found)
  end

  context "when configured" do
    before do
      allow(PkpassGenerator).to receive(:configured?).and_return(true)
      allow_any_instance_of(PkpassGenerator).to receive(:generate).and_return("PKPASSBYTES")
    end

    it "serves the pass for a confirmed ticket" do
      get apple_pass_path(confirmed_ticket.secret)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/vnd.apple.pkpass")
      expect(response.body).to eq("PKPASSBYTES")
    end

    it "returns 404 for an unknown ticket secret" do
      get apple_pass_path("does-not-exist")

      expect(response).to have_http_status(:not_found)
    end
  end
end
