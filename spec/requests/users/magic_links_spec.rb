require "rails_helper"

RSpec.describe "User magic links", type: :request do
  def verifier
    ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key("user_magic_link"),
      digest: "SHA256",
      serializer: JSON,
      url_safe: true
    )
  end

  it "sends a magic link to an existing user" do
    user = create(:user)

    expect {
      post user_magic_links_path, params: { email: user.email }
    }.to have_enqueued_mail(UserMagicLinkMailer, :link).with(user, String)

    expect(response).to redirect_to(login_path)
  end

  it "does not reveal whether an email exists" do
    expect {
      post user_magic_links_path, params: { email: "missing@example.com" }
    }.not_to have_enqueued_mail(UserMagicLinkMailer, :link)

    expect(response).to redirect_to(login_path)
    expect(flash[:notice]).to include("If that email")
  end

  it "signs in a user with a valid token" do
    user = create(:user)
    token = verifier.generate(user.id, purpose: :user_magic_link, expires_in: 15.minutes)

    expect { get user_magic_link_path(token:) }.to change(Session, :count).by(1)

    expect(response).to redirect_to(rails_health_check_url)
  end

  it "rejects an invalid or expired token" do
    get user_magic_link_path(token: "nope")

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to include("invalid")
  end
end
