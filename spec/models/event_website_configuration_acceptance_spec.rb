require "rails_helper"

RSpec.describe "Event website configuration acceptance", type: :model do
  def configuration(**changes)
    EventWebsites::Configuration.new(EventWebsites::Configuration.defaults.to_h.merge(changes.stringify_keys))
  end

  def contrast(first, second)
    luminances = [ first, second ].map do |color|
      channels = color.delete_prefix("#").scan(/../).map do |channel|
        value = channel.to_i(16) / 255.0
        value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
      end
      channels.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |value, weight| value * weight }
    end
    bright, dark = luminances.sort.reverse
    (bright + 0.05) / (dark + 0.05)
  end

  it "accepts only the three supported theme directions and preset heading fonts" do
    %w[conference marathon campus].each do |theme|
      expect(configuration(theme:).to_h.fetch("theme")).to eq(theme)
    end
    %w[editorial modern humanist].each do |font|
      expect(configuration(font:).to_h.fetch("font")).to eq(font)
    end
    [ { theme: "custom" }, { font: "url(https://external.example/font.css)" }, { accent: "#123" }, { surface: "transparent" }, { version: 2 } ].each do |changes|
      expect { configuration(**changes) }.to raise_error(EventWebsites::Configuration::Invalid)
    end
  end

  it "bounds plain content and rejects unknown fields and foreign navigation" do
    [
      { css: "body{}" }, { javascript: "alert(1)" }, { summary: "x" * 301 }, { about: "x" * 1201 },
      { venue_name: "x" * 101 }, { venue_address: "x" * 301 }, { venue_details: "x" * 601 },
      { navigation: [ "https://external.example" ] }, { sections: %w[about about] }, { sections: [ "unsupported" ] },
      { programme: Array.new(21) { { "time" => "09:00", "title" => "Talk", "speaker" => "Speaker" } } },
      { programme: [ { "time" => "x" * 61, "title" => "Talk", "speaker" => "Speaker" } ] },
      { programme: [ { "time" => "", "title" => "x" * 161, "speaker" => "" } ] },
      { programme: [ { "time" => "", "title" => "Talk", "speaker" => "x" * 121 } ] },
      { programme: [ { "time" => "", "title" => "Talk", "speaker" => "", "html" => "<b>unsafe</b>" } ] },
      { sponsors: Array.new(21) { { "name" => "Sponsor", "tier" => "Community" } } },
      { sponsors: [ { "name" => "x" * 121, "tier" => "" } ] },
      { sponsors: [ { "name" => "Sponsor", "tier" => "x" * 81 } ] },
      { sponsors: [ { "name" => "Sponsor", "tier" => "Community", "url" => "https://external.example" } ] },
      { assets: { "logo" => "https://external.example/logo.png" } }
    ].each do |changes|
      expect { configuration(**changes) }.to raise_error(EventWebsites::Configuration::Invalid), changes.inspect
    end
    expect(configuration(summary: "x" * 300, about: "x" * 1200, venue_name: "x" * 100, venue_address: "x" * 300, venue_details: "x" * 600).to_h.fetch("summary").length).to eq(300)
  end

  it "permits bounded ordered sections and owns every nested configuration object" do
    input = EventWebsites::Configuration.defaults.to_h.merge("sections" => %w[venue about], "navigation" => %w[venue about], "programme" => [ { "time" => "09:00", "title" => "Original", "speaker" => "Speaker" } ])
    config = EventWebsites::Configuration.new(input)
    input.fetch("programme").first["title"].replace("Mutated input")
    copy = config.to_h
    copy.fetch("programme").first["title"].replace("Mutated result")
    expect(config.to_h.fetch("programme").first.fetch("title")).to eq("Original")
    expect(config.to_h.fetch("sections")).to eq(%w[venue about])
  end

  it "derives foreground colors with at least 4.5 to 1 contrast for configured surfaces and accents" do
    %w[#000000 #ffffff #757575 #777777 #123456 #d8f250 #803c35].each do |color|
      tokens = configuration(accent: color, surface: color).tokens
      expect(contrast(color, tokens.fetch("--ew-accent-ink"))).to be >= 4.5
      expect(contrast(color, tokens.fetch("--ew-ink"))).to be >= 4.5
    end
  end
end
