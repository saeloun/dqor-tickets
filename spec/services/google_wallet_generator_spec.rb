require "rails_helper"

RSpec.describe GoogleWalletGenerator do
  before do
    @key = OpenSSL::PKey::RSA.new(2048)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_WALLET_ISSUER_ID").and_return("3388000000023172243")
    allow(ENV).to receive(:[]).with("GOOGLE_WALLET_SA_EMAIL").and_return("dqor@project.iam.gserviceaccount.com")
    allow(ENV).to receive(:[]).with("GOOGLE_WALLET_SA_KEY").and_return(@key.to_pem)
  end

  let(:ticket) do
    order = create(:order, :paid)
    create(:ticket, order:, attendee_name: "Ana Fan", attendee_email: "ana@example.com", assigned_at: Time.current, tshirt_size: "M")
  end

  it "reports configured with issuer + service account + key" do
    expect(described_class).to be_configured
  end

  it "builds a save URL with a valid signed JWT carrying the ticket" do
    url = described_class.new(ticket).save_url
    expect(url).to start_with("https://pay.google.com/gp/v/save/")

    token = url.split("/save/").last
    decoded, header = JWT.decode(token, @key.public_key, true, algorithm: "RS256")

    expect(header["alg"]).to eq("RS256")
    expect(decoded["iss"]).to eq("dqor@project.iam.gserviceaccount.com")
    expect(decoded["typ"]).to eq("savetowallet")

    object = decoded["payload"]["eventTicketObjects"].first
    expect(object["id"]).to eq("3388000000023172243.#{ticket.secret}")
    expect(object["barcode"]["value"]).to eq(ticket.secret)
    expect(object["ticketHolderName"]).to eq("Ana Fan")

    klass = decoded["payload"]["eventTicketClasses"].first
    expect(klass["id"]).to eq("3388000000023172243.dqor_event")
    expect(klass["eventName"]["defaultValue"]["value"]).to eq("Deccan Queen on Rails")
  end

  it "is not configured without the key" do
    allow(ENV).to receive(:[]).with("GOOGLE_WALLET_SA_KEY").and_return(nil)
    expect(described_class).not_to be_configured
  end

  it "is not published until GOOGLE_WALLET_PUBLISHED is enabled" do
    allow(ENV).to receive(:[]).with("GOOGLE_WALLET_PUBLISHED").and_return(nil)
    expect(described_class).to be_configured
    expect(described_class).not_to be_published
  end

  it "is published when configured and the publish flag is set" do
    allow(ENV).to receive(:[]).with("GOOGLE_WALLET_PUBLISHED").and_return("true")
    expect(described_class).to be_published
  end
end
