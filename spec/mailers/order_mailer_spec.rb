require "rails_helper"

RSpec.describe OrderMailer, type: :mailer do
  it "sends only the invoice and assignment link to the buyer" do
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
    expect(mail.attachments.map(&:filename)).to contain_exactly("invoice.pdf")
    expect(mail.html_part.body.to_s).to include(order.code, "2 tickets", "/orders/#{order.code}")
  end

  it "includes a private claim link for every ticket so the buyer can forward them" do
    order = create(:order, :paid, email: "buyer@example.com")
    unassigned = create(:ticket, order:, attendee_name: nil, attendee_email: nil)
    assigned = create(:ticket, order:, attendee_name: "Grace Hopper")
    canceled = create(:ticket, order:, canceled_at: Time.current)
    Invoice.issue_for!(order)

    mail = described_class.confirmation(order, documents_pending: true)
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s

    [ html, text ].each do |body|
      expect(body).to include(ticket_claim_url(unassigned.claim_token))
      expect(body).to include(ticket_claim_url(assigned.claim_token))
      expect(body).not_to include(ticket_claim_url(canceled.claim_token))
    end
    expect(html).to include("Grace Hopper", "update details")
  end

  it "sends the order permalink with a claim link per ticket" do
    order = create(:order, :paid, email: "buyer@example.com", buyer_name: "Ada Lovelace")
    unassigned = create(:ticket, order:, attendee_name: nil, attendee_email: nil)
    assigned = create(:ticket, order:, attendee_name: "Grace Hopper")
    canceled = create(:ticket, order:, canceled_at: Time.current)

    mail = described_class.order_link(order)

    expect(mail.to).to eq([ "buyer@example.com" ])
    expect(mail.subject).to eq("Your Deccan Queen on Rails order link")
    expect(mail.attachments).to be_empty
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      expect(body).to include(order_url(order.code))
      expect(body).to include(ticket_claim_url(unassigned.claim_token))
      expect(body).to include(ticket_claim_url(assigned.claim_token))
      expect(body).not_to include(ticket_claim_url(canceled.claim_token))
    end
    expect(mail.html_part.body.to_s).to include("1 ticket still", "Grace Hopper")
  end

  it "sends a confirmation link without attachments while documents are pending" do
    order = create(:order, :paid, email: "buyer@example.com")

    mail = described_class.confirmation(order, documents_pending: true)

    expect(mail.attachments).to be_empty
    expect(mail.text_part.body.to_s).to include("being prepared", order_url(order.code))
    expect(described_class.delivery_job).to eq(MailDeliveryJob)
  end

  it "sends one ticket PDF to the assigned attendee" do
    ticket = create(:ticket, attendee_name: "Grace Hopper", attendee_email: "grace@example.com")
    ticket.pdf.attach(io: StringIO.new("ticket"), filename: "ticket.pdf", content_type: "application/pdf")

    mail = described_class.ticket(ticket)

    expect(mail.to).to eq([ "grace@example.com" ])
    expect(mail.subject).to eq("Your Deccan Queen on Rails ticket")
    expect(mail.attachments.map(&:filename)).to contain_exactly("ticket.pdf")
    expect(mail.html_part.body.to_s).to include("Grace Hopper", ticket.ticket_type.name)
  end
end
