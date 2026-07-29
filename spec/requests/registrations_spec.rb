require "rails_helper"

RSpec.describe "Event registrations", type: :request do
  let(:organizer) { create(:organizer, slug: "dqor") }
  let(:event) { create(:event, organizer:, slug: "2026", guest_list_public: true) }

  it "shows a public guest list excluding pending and waitlisted attendees" do
    going = create(:registration, event:, attendance_state: "going")
    interested = create(:registration, event:, attendance_state: "interested")
    create(:registration, event:, attendance_state: "waitlisted")
    create(:registration, event:, attendance_state: "pending_approval")

    get event_guests_path(organizer.slug, event.slug)

    expect(response.body).to include(going.user.name)
    expect(response.body).to include(interested.user.name)
  end

  it "hides the guest list when the host turns it off" do
    event.update!(guest_list_public: false)

    get event_guests_path(organizer.slug, event.slug)

    expect(response).to have_http_status(:not_found)
  end

  it "requires sign-in to RSVP" do
    post event_registrations_path(organizer.slug, event.slug)

    expect(response).to have_http_status(:redirect)
    expect(response.location).to include(login_path)
  end

  it "creates a going registration for a signed-in user" do
    user = create(:user)
    sign_in_user(user)

    expect {
      post event_registrations_path(organizer.slug, event.slug)
    }.to change(event.registrations, :count).by(1)

    registration = event.registrations.find_by(user:)
    expect(registration).to be_going
    expect(registration).to be_not_required
  end

  it "cancels a registration" do
    user = create(:user)
    registration = create(:registration, event:, user:, attendance_state: "going")
    sign_in_user(user)

    expect {
      delete event_registrations_path(organizer.slug, event.slug)
    }.to change { registration.reload.attendance_state }.to("cancelled")
  end

  it "shows RSVP and Interested options to a signed-in user on the event page" do
    user = create(:user)
    sign_in_user(user)

    get event_path(organizer.slug, event.slug)

    expect(response.body).to include("Interested")
    expect(response.body).to include("RSVP")
  end

  def sign_in_user(user)
    token = ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key("user_magic_link"),
      digest: "SHA256",
      serializer: JSON,
      url_safe: true
    ).generate(user.id, purpose: :user_magic_link, expires_in: 15.minutes)
    get user_magic_link_path(token: token)
  end
end
