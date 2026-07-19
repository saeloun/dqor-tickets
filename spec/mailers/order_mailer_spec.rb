require "rails_helper"

RSpec.describe OrderMailer, type: :mailer do
  it "sends the invoice and each ticket PDF to the buyer" do
    order = create(:order, :paid, email: "buyer@example.com")
    tickets = create_list(:ticket, 2, order:)
    invoice = Invoice.issue_for!(order)
    invoice.pdf.attach(io: StringIO.new("invoice"), filename: "invoice.pdf", content_type: "application/pdf")
    tickets.each_with_index do |ticket, index|
      ticket.pdf.attach(io: StringIO.new("ticket #{index}"), filename: "ticket-#{index}.pdf", content_type: "application/pdf")
    end

    mail = described_class.confirmation(order)

    expect(mail.to).to eq([ "buyer@example.com" ])
    expect(mail.subject).to eq("Your Deccan Queen on Rails tickets")
    expect(mail.attachments.map(&:filename)).to contain_exactly("invoice.pdf", "ticket-0.pdf", "ticket-1.pdf")
    expect(mail.html_part.body.to_s).to include(order.code, "/orders/#{order.code}")
  end

  it "sends a confirmation link without attachments while documents are pending" do
    order = create(:order, :paid, email: "buyer@example.com")

    mail = described_class.confirmation(order, documents_pending: true)

    expect(mail.attachments).to be_empty
    expect(mail.text_part.body.to_s).to include("being prepared", order_url(order.code))
    expect(described_class.delivery_job).to eq(MailDeliveryJob)
  end
end
