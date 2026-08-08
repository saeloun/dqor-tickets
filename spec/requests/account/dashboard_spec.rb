require "rails_helper"

RSpec.describe "Account dashboard hub", type: :request do
  def sign_in_as(user)
    get account_magic_path(
      token: Rails.application.message_verifier(:account_magic_link)
        .generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    )
  end

  it "requires sign-in" do
    get account_root_path

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "shows the countdown and quick-action tiles before the event" do
    allow(Conference).to receive(:status).and_return(:before)
    allow(Conference).to receive(:days_to_go).and_return(42)
    sign_in_as(User.create!(email: "hub@example.com", name: "Hub Tester"))

    get account_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("hub-countdown")
    expect(response.body).to include("42")
    expect(response.body).to include("to go")
    # Quick-action tiles link out to the hub destinations.
    expect(response.body).to include("Schedule")
    expect(response.body).to include("Attendees")
    expect(response.body).to include("Venue &amp; travel")
    expect(response.body).to include("Concierge")
    expect(response.body).to include(community_path)
    expect(response.body).to include(schedule_path)
  end

  it "shows a live banner during the event" do
    allow(Conference).to receive(:status).and_return(:during)
    sign_in_as(User.create!(email: "live@example.com", name: "Live Tester"))

    get account_root_path

    expect(response.body).to include("Happening now")
  end

  it "hides the countdown once the event has passed" do
    allow(Conference).to receive(:status).and_return(:after)
    sign_in_as(User.create!(email: "past@example.com", name: "Past Tester"))

    get account_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("hub-countdown")
    # Quick actions still render as the persistent hub navigation.
    expect(response.body).to include("hub-actions")
  end
end
