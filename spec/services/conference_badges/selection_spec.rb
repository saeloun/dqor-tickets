require "rails_helper"

RSpec.describe ConferenceBadges::Selection do
  let(:type) { create(:ticket_type, slug: "conference-pass-regular") }
  let(:paid) { create(:order, :paid) }
  let(:ticket) { create(:ticket, ticket_type: type, order: paid, attendee_name: "Synthetic Ada") }

  def build(ids = [ ticket.id ], companies: {}, confirmed: true)
    described_class.build(ids:, companies:, confirmed:)
  end

  it "keeps paid, supporter and valid complimentary passes as distinct badges" do
    supporter = create(:ticket, order: paid, ticket_type: create(:ticket_type, slug: "supporter-pass"))
    comp = create(:ticket, order: create(:order, :paid, total_paise: 0), ticket_type: create(:ticket_type, slug: "complimentary-pass", hidden: true, price_paise: 0))

    expect(build([ ticket.id, supporter.id, comp.id ]).map(&:ticket_id)).to match_array([ ticket.id, supporter.id, comp.id ])
  end

  [ "rails-girls-pune", "explore-pune-day", "other-pass" ].each do |slug|
    it "refuses #{slug} inventory" do
      other = create(:ticket, order: paid, ticket_type: create(:ticket_type, slug:))
      expect { build([ other.id ]) }.to raise_error(described_class::Invalid, /confirmed conference pass/)
    end
  end

  [ :pending, :expired, :canceled ].each do |status|
    it "refuses #{status} orders" do
      ticket.order.update!(status:)
      expect { build }.to raise_error(described_class::Invalid, /confirmed conference pass/)
    end
  end

  it "revalidates a pass canceled after roster selection" do
    selected = ticket.id
    ticket.update!(canceled_at: Time.current)
    expect { build([ selected ]) }.to raise_error(described_class::Invalid, /confirmed conference pass/)
  end

  it "fails the entire selection when one ID is unknown" do
    expect { build([ ticket.id, 9_999_999 ]) }.to raise_error(described_class::Invalid)
  end

  it "requires explicit confirmation and a nonempty bounded ID array" do
    [ nil, false, "1" ].each { |confirmation| expect { build(confirmed: confirmation) }.to raise_error(described_class::Invalid) }
    [ [], [ "invalid" ], [ ticket.id ] * 51, ticket.id ].each { |ids| expect { build(ids) }.to raise_error(described_class::Invalid) }
  end

  it "rejects repeated pass IDs rather than silently deduplicating" do
    expect { build([ ticket.id, ticket.id ]) }.to raise_error(described_class::Invalid, /once/)
  end

  it "does not print an unnamed attendee or truncate an overlong name" do
    ticket.update!(attendee_name: " ")
    expect { build }.to raise_error(described_class::Invalid, /attendee name/)
    ticket.update!(attendee_name: "W" * 121)
    expect { build }.to raise_error(described_class::Invalid, /120/)
  end

  it "flags normalized duplicate names and emails without removing distinct passes" do
    first = ticket
    second = create(:ticket, order: paid, ticket_type: type, attendee_name: " synthetic  ADA ")
    third = create(:ticket, order: paid, ticket_type: type, attendee_name: "Different name", attendee_email: first.attendee_email.upcase)

    badges = build([ first.id, second.id, third.id ])
    expect(badges.length).to eq(3)
    expect(badges.map(&:duplicate)).to all(be(true))
  end

  it "orders names deterministically, then pass IDs, and defaults company to blank" do
    zed = create(:ticket, order: paid, ticket_type: type, attendee_name: "Zed")
    first = ticket
    second = create(:ticket, order: paid, ticket_type: type, attendee_name: first.attendee_name.upcase)

    badges = build([ zed.id, second.id, first.id ])
    expect(badges.map(&:ticket_id)).to eq([ first.id, second.id, zed.id ])
    expect(badges.map(&:company)).to all(eq(""))
  end

  it "allows bounded selected-pass company text only without persisting or admitting" do
    before = ticket.attributes
    badge = build(companies: { ticket.id.to_s => "W" * 80 }).first
    expect(badge.company).to eq("W" * 80)
    expect(ticket.reload.attributes).to eq(before)
    expect(CheckinAudit.count).to eq(0)
    expect(EventSlotRedemption.count).to eq(0)
    expect(ActiveStorage::Attachment.count).to eq(0)
    [ { "other" => "Company" }, { ticket.id.to_s => "W" * 81 }, { ticket.id.to_s => "Line\nBreak" }, { ticket.id.to_s => {} } ].each do |companies|
      expect { build(companies:) }.to raise_error(described_class::Invalid)
    end
  end

  it "has an explicit four-module white QR quiet zone and no text payload" do
    svg = Nokogiri::XML(build.first.qr_svg)
    qr = RQRCode::QRCode.new(ticket.secret, level: :h)
    dimension = qr.modules.length + 8
    expect(svg.at_css("svg")["viewBox"]).to eq("0 0 #{dimension} #{dimension}")
    expect(svg.at_css("rect")["fill"]).to eq("#ffffff")
    expect(svg.at_css("rect")["width"]).to eq(dimension.to_s)
    expect(svg.at_css("path")["transform"]).to eq("translate(4,4) scale(1)")
    expect(svg.to_xml).not_to include(ticket.secret, ticket.claim_token)
  end

  it "creates unmistakable synthetic rehearsal badges without ticket reads" do
    expect(ConferenceInventory).not_to receive(:confirmed)
    expect(described_class.sample).to all(have_attributes(sample: true, ticket_id: nil))
  end
end
