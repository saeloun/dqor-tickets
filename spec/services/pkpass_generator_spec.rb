require "rails_helper"
require "zip"

RSpec.describe PkpassGenerator do
  before do
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    name = OpenSSL::X509::Name.parse("/CN=Test Pass")
    cert.subject = name
    cert.issuer = name
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest.new("SHA256"))

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("APPLE_PASS_CERT").and_return(cert.to_pem)
    allow(ENV).to receive(:[]).with("APPLE_PASS_KEY").and_return(key.to_pem)
    allow(ENV).to receive(:[]).with("APPLE_PASS_KEY_PASSWORD").and_return(nil)
    allow(ENV).to receive(:[]).with("APPLE_PASS_TYPE_ID").and_return("pass.com.test.ticket")
    allow(ENV).to receive(:[]).with("APPLE_TEAM_ID").and_return("TEAM123456")
  end

  let(:ticket) do
    order = create(:order, :paid)
    create(:ticket, order:, attendee_name: "Ana Fan", attendee_email: "ana@example.com", assigned_at: Time.current, tshirt_size: "M")
  end

  it "reports configured when the cert env is present" do
    expect(described_class).to be_configured
  end

  it "builds a signed .pkpass with the required files and a matching manifest" do
    data = described_class.new(ticket).generate

    entries = {}
    Zip::InputStream.open(StringIO.new(data)) do |io|
      while (entry = io.get_next_entry)
        entries[entry.name] = io.read
      end
    end

    expect(entries.keys).to include("pass.json", "manifest.json", "signature", "icon.png", "icon@2x.png", "logo.png")

    pass = JSON.parse(entries["pass.json"])
    expect(pass["passTypeIdentifier"]).to eq("pass.com.test.ticket")
    expect(pass["teamIdentifier"]).to eq("TEAM123456")
    expect(pass["barcodes"].first["message"]).to eq(ticket.secret)
    expect(pass["serialNumber"]).to eq(ticket.secret)

    manifest = JSON.parse(entries["manifest.json"])
    expect(manifest["pass.json"]).to eq(Digest::SHA1.hexdigest(entries["pass.json"]))
    expect(manifest["icon.png"]).to eq(Digest::SHA1.hexdigest(entries["icon.png"]))

    expect(entries["signature"].bytesize).to be > 100
  end

  it "is not configured without the cert" do
    allow(ENV).to receive(:[]).with("APPLE_PASS_CERT").and_return(nil)
    expect(described_class).not_to be_configured
  end
end
