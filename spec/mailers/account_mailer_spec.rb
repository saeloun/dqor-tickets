require "rails_helper"

RSpec.describe AccountMailer do
  it "renders the magic-link email" do
    user = User.create!(email: "grace@example.com")

    mail = AccountMailer.magic_link(user, "TOKEN123")

    expect(mail.to).to eq([ "grace@example.com" ])
    expect(mail.subject).to match(/sign-in link/i)
    expect(mail.body.encoded).to include("TOKEN123")
  end
end
