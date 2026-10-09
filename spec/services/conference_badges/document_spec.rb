require "rails_helper"
require "open3"

RSpec.describe ConferenceBadges::Document do
  def browser
    options = { browser_path: ENV.fetch("CHROME_PATH"), timeout: 30, process_timeout: 30 }
    options[:browser_options] = { "no-sandbox" => nil, "disable-dev-shm-usage" => nil } if ENV["CHROME_NO_SANDBOX"] == "1"
    @browser ||= Ferrum::Browser.new(**options)
  end

  after { @browser&.quit }

  def pdf_tool(name)
    tool = ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |directory| File.join(directory, name) }.find { |path| File.executable?(path) && !File.directory?(path) }
    raise "PDF verification requires #{name} on PATH (install poppler-utils in CI); verification must not be skipped" unless tool

    tool
  end

  def decode_pdf(badges)
    pdf = described_class.pdf(badges)
    browser.content = described_class.html(badges)
    browser.page.command("Emulation.setEmulatedMedia", media: "print")
    boxes = browser.evaluate("Array.from(document.querySelectorAll('.badge-qr'), element => { const r = element.getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height}; })")
    cards = browser.evaluate("Array.from(document.querySelectorAll('.conference-badge'), element => { const r = element.getBoundingClientRect(); return {width:r.width,height:r.height}; })")
    cards.each do |card|
      expect(card.fetch("width") * 25.4 / 96).to be_within(0.05).of(90)
      expect(card.fetch("height") * 25.4 / 96).to be_within(0.05).of(120)
    end
    boxes.each do |box|
      expect(box.fetch("width") * 25.4 / 96).to be >= 32
      expect(box.fetch("height")).to be_within(0.01).of(box.fetch("width"))
    end
    browser.execute(Rails.root.join("vendor/javascript/jsqr-1.4.0.js").read)
    Dir.mktmpdir("dqor-badge-decode") do |directory|
      path = File.join(directory, "badges.pdf")
      image = File.join(directory, "raster")
      File.binwrite(path, pdf)
      _out, error, result = Open3.capture3(pdf_tool("pdftoppm"), "-f", "1", "-singlefile", "-r", "300", "-png", path, image)
      expect(result.success?).to be(true), error
      data = "data:image/png;base64,#{Base64.strict_encode64(File.binread("#{image}.png"))}"
      decoded = browser.evaluate_async(<<~JS, 30, data, boxes)
        const [data, boxes, done] = arguments;
        const image = new Image();
        image.onload = () => done(boxes.map(box => {
          const canvas = document.createElement('canvas');
          canvas.width = Math.round(box.width * 300 / 96);
          canvas.height = Math.round(box.height * 300 / 96);
          const context = canvas.getContext('2d');
          context.drawImage(image, box.x * 300 / 96, box.y * 300 / 96, box.width * 300 / 96, box.height * 300 / 96, 0, 0, canvas.width, canvas.height);
          const pixels = context.getImageData(0, 0, canvas.width, canvas.height);
          return window.jsQR(pixels.data, canvas.width, canvas.height)?.data || null;
        }));
        image.onerror = () => done(['image-error']);
        image.src = data;
      JS
      decoded
    end
  end

  it "refuses a missing or partially rendered badge layout instead of returning an empty PDF" do
    sample = ConferenceBadges::Selection.sample
    allow(described_class).to receive(:html).and_return("<!DOCTYPE html><html><body></body></html>")
    expect { described_class.preview(sample) }.to raise_error(ConferenceBadges::Selection::Invalid, /layout could not be verified/)
    expect { described_class.pdf(sample) }.to raise_error(ConferenceBadges::Selection::Invalid, /layout could not be verified/)
  end

  it "renders a real A4 two-page PDF for five badges and keeps private ticket fields out of extracted text" do
    type = create(:ticket_type, slug: "conference-pass-regular")
    order = create(:order, :paid, email: "private-buyer@example.com", buyer_phone: "9988776655", gstin: "27AAAAA0000A1Z5", billing_state_code: "27")
    tickets = create_list(:ticket, 5, order:, ticket_type: type, attendee_name: "Synthetic Badge", attendee_email: "private-person@example.com", dietary_preference: "private-diet")
    badges = ConferenceBadges::Selection.build(ids: tickets.map(&:id), companies: {}, confirmed: true)
    pdf = described_class.pdf(badges)

    expect(pdf).to start_with("%PDF-")
    Dir.mktmpdir("dqor-badge-pdf") do |directory|
      path = File.join(directory, "badges.pdf")
      File.binwrite(path, pdf)
      info, error, result = Open3.capture3(pdf_tool("pdfinfo"), path)
      expect(result.success?).to be(true), error
      expect(info).to match(/Pages:\s+2/)
      expect(info).to match(/Page size:\s+59[45]\.\d+ x 84[12]\.\d+ pts \(A4\)/)
      text, error, result = Open3.capture3(pdf_tool("pdftotext"), path, "-")
      expect(result.success?).to be(true), error
      expect(text).to include("Synthetic Badge", "Deccan Queen", "Duplicate attendee identity")
      expect(text).not_to include(order.email, order.buyer_phone, order.gstin, "private-person@example.com", "private-diet", *tickets.flat_map { |ticket| [ ticket.secret, ticket.claim_token ] })
    end
    expect(tickets.map { |ticket| ticket.reload.checked_in_at }).to all(eq({}))
    expect(CheckinAudit.count).to eq(0)
    expect(ActiveStorage::Attachment.count).to eq(0)
  end

  it "decodes all four actual generated PDF QR pixel regions with the bundled software decoder" do
    type = create(:ticket_type, slug: "conference-pass-regular")
    tickets = create_list(:ticket, 4, ticket_type: type, order: create(:order, :paid))
    badges = ConferenceBadges::Selection.build(ids: tickets.map(&:id), companies: {}, confirmed: true)
    decoded = decode_pdf(badges)

    expect(decoded).to eq(badges.map { |badge| tickets.find { |ticket| ticket.id == badge.ticket_id }.secret })
    expect(decoded.map(&:length)).to all(eq(24))
    expect(decoded).not_to include(*tickets.map(&:claim_token))
    expect(decoded).not_to include(*tickets.map { |ticket| "https://deccanqueenonrails.com/community/#{ticket.id}" })
    expect(CheckinAudit.count).to eq(0)
  end

  it "decodes every printed sample as the synthetic rehearsal QR without admission records" do
    badges = ConferenceBadges::Selection.sample
    expect(decode_pdf(badges)).to eq([ ScannerRehearsalsController::TEST_QR ] * 4)
    expect(Ticket.count).to eq(0)
    expect(CheckinAudit.count).to eq(0)
    text = Nokogiri::HTML(described_class.html(badges)).text
    expect(text.scan("NOT ADMISSION").length).to eq(8)
  end

  it "fits the longest permitted unbroken name and company inside measured print margins without truncation" do
    badge = ConferenceBadges::Selection.sample.first.with(name: "W" * 120, company: "W" * 80)
    html = described_class.preview([ badge ])
    expect(Nokogiri::HTML(html).at_css(".badge-name").text).to eq("W" * 120)
    expect(Nokogiri::HTML(html).at_css(".badge-company").text).to eq("W" * 80)
    expect(described_class.pdf([ badge ])).to start_with("%PDF-")
  end

  it "keeps ordinary Unicode names exact and refuses measured layout overflow with review guidance" do
    badge = ConferenceBadges::Selection.sample.first.with(name: "आरती पाटील", company: "東京 Ruby")
    expect(Nokogiri::HTML(described_class.preview([ badge ])).at_css(".badge-name").text).to eq("आरती पाटील")
    allow(described_class).to receive(:html).and_wrap_original do |renderer, badges|
      renderer.call(badges).sub("</style>", ".badge-name { font-size: 120pt !important; line-height: 1.2 !important; }</style>")
    end
    oversized = badge.with(name: "界" * 120, company: "界" * 80)
    browser.content = described_class.html([ oversized ])
    browser.page.command("Emulation.setEmulatedMedia", media: "print")
    dimensions = browser.evaluate("[document.querySelector('.badge-name').getBoundingClientRect().height, document.querySelector('.conference-badge').getBoundingClientRect().height]")
    expect(dimensions.first).to be > dimensions.last
    expect { described_class.preview([ oversized ]) }.to raise_error(ConferenceBadges::Selection::Invalid, /does not fit.*Review/)
    expect { described_class.pdf([ oversized ]) }.to raise_error(ConferenceBadges::Selection::Invalid, /does not fit.*Review/)
  end
end
