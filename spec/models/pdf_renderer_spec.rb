require "rails_helper"

RSpec.describe PdfRenderer, type: :model do
  def render(record, template:)
    described_class.render(record, template:)
  rescue Ferrum::BinaryNotFoundError => error
    skip "Chrome binary is unavailable: #{error.message}"
  end

  def expect_pdf(pdf)
    expect(pdf).to start_with("%PDF-")
    expect(pdf.bytesize).to be > 5_000
  end

  it "renders a branded GST invoice as a non-trivial PDF" do
    order = create(:order, :paid, gstin: "27AAAAA0000A1Z5", gst_legal_name: "Ada Labs Pvt Ltd", billing_state_code: "27")
    create(:ticket, order:)
    invoice = Invoice.issue_for!(order)

    expect_pdf(render(invoice, template: :invoice))
  end

  it "renders a branded ticket with its QR code as a non-trivial PDF" do
    ticket = create(:ticket)

    expect_pdf(render(ticket, template: :ticket))
  end

  it "disables the Chromium sandbox when configured" do
    browser = instance_double(Ferrum::Browser, pdf: "%PDF-test", quit: nil)
    allow(browser).to receive(:content=)
    allow(ApplicationController).to receive(:render).and_return("<html></html>")
    allow(Ferrum::Browser).to receive(:new).and_return(browser)
    previous_value = ENV["CHROME_NO_SANDBOX"]
    ENV["CHROME_NO_SANDBOX"] = "1"

    render(Object.new, template: :invoice)

    expect(Ferrum::Browser).to have_received(:new).with(hash_including(browser_options: {
      "no-sandbox" => nil,
      "disable-gpu" => nil,
      "disable-dev-shm-usage" => nil
    }))
  ensure
    ENV["CHROME_NO_SANDBOX"] = previous_value
  end
end
