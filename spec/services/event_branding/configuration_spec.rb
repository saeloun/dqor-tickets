require "spec_helper"
require_relative "../../../app/services/event_branding/configuration"

RSpec.describe EventBranding::Configuration do
  let(:configuration) { described_class.defaults.to_h }

  it "accepts each preset and generates only the renderer's supported CSS tokens" do
    described_class::THEMES.each do |theme|
      preset = described_class.defaults(theme)
      expect(preset.to_h.fetch("theme")).to eq(theme)
      expect(preset.tokens.keys).to contain_exactly("--dq-accent", "--dq-accent-ink", "--dq-surface", "--dq-ink", "--dq-display-font")
    end
  end

  it "rejects unknown properties and event identity changes" do
    %w[css script name date venue event_id tenant_id].each do |field|
      expect { described_class.new(configuration.merge(field => "untrusted")) }.to raise_error(described_class::Invalid)
    end
  end

  it "rejects unsupported schemas, theme names, fonts, and CSS injection" do
    [ [ "version", 2 ], [ "theme", "__proto__" ], [ "font", "url(https://example.com)" ], [ "accent", "#fff; background:url(https://example.com)" ], [ "surface", "transparent" ] ].each do |key, value|
      expect { described_class.new(configuration.merge(key => value)) }.to raise_error(described_class::Invalid)
    end
  end

  it "requires every supported section once and preserves the selected order" do
    [ [], %w[about about visit], %w[about programme arbitrary], [ nil, "about", "visit" ] ].each do |sections|
      expect { described_class.new(configuration.merge("sections" => sections)) }.to raise_error(described_class::Invalid)
    end
    sections = %w[visit programme about]
    expect(described_class.new(configuration.merge("sections" => sections)).to_h.fetch("sections")).to eq(sections)
  end

  it "accepts only managed positive asset IDs, never URLs, SVG, data or markup" do
    [ "https://example.com/image.png", "data:image/svg+xml;base64,abc", "<img src=x>", -1, 0, 1.1, "12", 2**64, nil ].each do |asset|
      expect { described_class.new(configuration.merge("assets" => { "logo" => asset })) }.to raise_error(described_class::Invalid)
    end
    expect { described_class.new(configuration.merge("assets" => { "script" => 12 })) }.to raise_error(described_class::Invalid)
    expect(described_class.new(configuration.merge("assets" => { "logo" => 12, "favicon" => 12 })).asset_ids).to eq([ 12 ])
  end

  it "does not let caller mutations alter an already validated snapshot" do
    subject = described_class.new(configuration)
    configuration["sections"].clear
    configuration["accent"].replace("invalid")
    output = subject.to_h
    output["assets"]["logo"] = "untrusted"
    subject.tokens.fetch("--dq-accent").replace("invalid")
    expect(subject.to_h).to eq(described_class.defaults.to_h)
  end

  it "selects legible foreground colors on very light and dark surfaces" do
    expect(described_class.new(configuration.merge("surface" => "#ffffff", "accent" => "#000000")).tokens).to include("--dq-ink" => "#000000", "--dq-accent-ink" => "#ffffff")
  end
end
