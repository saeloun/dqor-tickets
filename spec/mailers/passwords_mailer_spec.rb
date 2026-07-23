require "rails_helper"

RSpec.describe PasswordsMailer, type: :mailer do
  let(:admin_user) { create(:admin_user, email: "admin@example.com") }

  it "sends the reset instructions to the admin who asked" do
    mail = described_class.reset(admin_user)

    expect(mail.to).to eq([ "admin@example.com" ])
    expect(mail.subject).to eq("Reset your password")
    expect(mail.attachments).to be_empty
  end

  it "carries a reset URL whose token the reset flow can actually use" do
    mail = described_class.reset(admin_user)
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s

    [ html, text ].each do |body|
      match = body.match(%r{https?://\S*?/passwords/([^/\s"'<]+)/edit})
      expect(match).to be_present

      token = URI::DEFAULT_PARSER.unescape(match[1])
      expect(match[0]).to eq(edit_password_url(token))
      expect(AdminUser.find_by_password_reset_token!(token)).to eq(admin_user)
    end
  end

  it "states the expiry the model actually enforces" do
    mail = described_class.reset(admin_user)
    expiry = ActionController::Base.helpers.distance_of_time_in_words(0, admin_user.password_reset_token_expires_in)
    stated = "expires in #{expiry}"

    expect(admin_user.password_reset_token_expires_in).to eq(15.minutes)
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      expect(body).to include(stated)
    end
  end

  it "always ships an HTML part and a non-empty plain text part" do
    mail = described_class.reset(admin_user)

    expect(mail).to be_multipart
    expect(mail.html_part).to be_present
    expect(mail.text_part).to be_present
    expect(mail.text_part.body.to_s.strip).not_to be_empty
    expect(mail.html_part.content_type).to start_with("text/html")
    expect(mail.text_part.content_type).to start_with("text/plain")
  end

  it "wraps the message in the shared branded layout" do
    mail = described_class.reset(admin_user)
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
    html = described_class.reset(admin_user).html_part.body.to_s

    expect(html).not_to include("#9a7b3a")
    expect(html).not_to include("#9a8560")
  end
end
