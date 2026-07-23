require "rails_helper"

RSpec.describe TicketAccessMailer, type: :mailer do
  def access_token(email = "buyer@example.com")
    Rails.application.message_verifier(:ticket_access).generate(
      email,
      purpose: TicketAccessController::TOKEN_PURPOSE,
      expires_in: TicketAccessController::TOKEN_EXPIRY
    )
  end

  it "sends the access link to the address that asked for it" do
    mail = described_class.link("buyer@example.com", access_token)

    expect(mail.to).to eq([ "buyer@example.com" ])
    expect(mail.subject).to eq("Your Deccan Queen on Rails tickets")
    expect(mail.attachments).to be_empty
    expect(mail.from).to eq([ ENV.fetch("MAIL_FROM", "tickets@deccanqueenonrails.com") ])
  end

  it "carries the token as a query parameter, never in the URL path" do
    token = access_token
    expected = ticket_access_url(token: token)

    mail = described_class.link("buyer@example.com", token)
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s

    expect(expected).to start_with("http://example.com/tickets/access?token=")

    [ html, text ].each do |body|
      expect(body).to include(expected)
      expect(body).to match(%r{/tickets/access\?token=})
      expect(body).not_to match(%r{/tickets/access/[^\s"'?]})
    end
  end

  it "tells the reader the link is good for 24 hours" do
    mail = described_class.link("buyer@example.com", access_token)

    expect(TicketAccessController::TOKEN_EXPIRY).to eq(24.hours)
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      expect(body).to include("24 hours")
    end
  end

  it "always ships an HTML part and a non-empty plain text part" do
    mail = described_class.link("buyer@example.com", access_token)

    expect(mail).to be_multipart
    expect(mail.html_part).to be_present
    expect(mail.text_part).to be_present
    expect(mail.text_part.body.to_s.strip).not_to be_empty
    expect(mail.html_part.content_type).to start_with("text/html")
    expect(mail.text_part.content_type).to start_with("text/plain")
  end

  it "wraps the message in the shared branded layout" do
    mail = described_class.link("buyer@example.com", access_token)
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s

    expect(html).to include('<meta name="robots" content="noindex,nofollow">')
    expect(html).to include("Deccan Queen on Rails", "Hyatt Regency Pune")
    expect(html).to include(
      "mailto:hello@deccanqueenonrails.com",
      "https://deccanqueenonrails.com",
      "https://tickets.deccanqueenonrails.com"
    )
    expect(text).to include("DECCAN QUEEN ON RAILS", "Hyatt Regency Pune")
    expect(text).to include(
      "hello@deccanqueenonrails.com",
      "https://deccanqueenonrails.com",
      "https://tickets.deccanqueenonrails.com"
    )
  end

  it "keeps the two low-contrast golds out of the rendered HTML" do
    html = described_class.link("buyer@example.com", access_token).html_part.body.to_s

    expect(html).not_to include("#9a7b3a")
    expect(html).not_to include("#9a8560")
  end
end
