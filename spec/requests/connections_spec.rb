require "rails_helper"

RSpec.describe "Connections", type: :request do
  def sign_in_as(user)
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  it "connects with and disconnects from a discoverable attendee" do
    me = User.create!(email: "me@example.com")
    ada = User.create!(email: "ada@example.com", name: "Ada", discoverable: true)
    sign_in_as(me)

    expect {
      post connect_attendee_path(ada)
    }.to change { me.connections.count }.by(1)
    expect(me.connected_to?(ada)).to be(true)

    expect {
      delete disconnect_attendee_path(ada)
    }.to change { me.connections.count }.by(-1)
  end

  it "connects with a non-discoverable attendee reached through a direct profile link" do
    me = User.create!(email: "me@example.com")
    hidden = User.create!(email: "hidden@example.com", name: "Hidden Attendee", discoverable: false)
    sign_in_as(me)

    get attendee_path(hidden)
    expect(response).to have_http_status(:ok)

    expect {
      post connect_attendee_path(hidden)
    }.to change { me.connections.count }.by(1)
    expect(response).to redirect_to(attendee_path(hidden))
    expect(me).to be_connected_to(hidden)
  end
end
