require "rails_helper"

RSpec.describe "RSVP flow", type: :system do
  let(:organizer) { create(:organizer, slug: "dqor") }
  let(:event) { create(:event, organizer:, slug: "2026", guest_list_public: true, status: "published") }

  it "browses an event, signs in via magic link, and RSVPs", skip: "E2E browser flow finalized in the P10 Luma-UI phase (async deliver_later magic-link mail is not captured from the system-test server thread). The underlying magic-link login and RSVP creation are covered by spec/requests/registrations_spec.rb and the mailer/model specs." do
    user = create(:user)

    visit event_path(organizer.slug, event.slug)
    expect(page).to have_content(event.title)

    click_on "Sign in to RSVP"
    expect(page).to have_content("Sign in")

    click_on "Email me a magic link"
    fill_in "Email address", with: user.email
    click_on "Send sign-in link"

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to include(user.email)

    token = mail.body.to_s[/user\/magic-link\/([A-Za-z0-9_-]+)/, 1]
    visit user_magic_link_path(token: token)
    visit event_path(organizer.slug, event.slug)

    click_on "RSVP"
    expect(page).to have_content("You are going")
  end

  it "RSVPs as interested when already signed in" do
    user = create(:user)
    token = ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key("user_magic_link"),
      digest: "SHA256",
      serializer: JSON,
      url_safe: true
    ).generate(user.id, purpose: :user_magic_link, expires_in: 15.minutes)

    visit user_magic_link_path(token: token)
    visit event_path(organizer.slug, event.slug)
    click_on "Interested"

    expect(page).to have_content("You are interested")
  end
end
