require "rails_helper"

RSpec.describe Discovery::CanonicalUrl do
  it "rejects browser IPv4 forms that strict IP parsing does not recognize" do
    %w[127.1 0x7f.0.0.1 192.168.1 0177.0.0.1 127.0.0x1 127.0.0.0x 127.0.0.0X 127.0.01 1.2.3.999 1.2.3.0xdead].each do |host|
      url = "https://#{host}/"
      expect { described_class.call(url) }.to raise_error(described_class::Invalid), host
      expect(described_class.safe(url)).to be_nil, host
    end
  end

  it "preserves public DNS names containing digits and punycode labels" do
    %w[github.com 2026.example.com events2026.example.com xn--bcher-kva.example.com].each do |host|
      expect(described_class.call("https://#{host}/")).to eq("https://#{host}/")
    end
  end
end
