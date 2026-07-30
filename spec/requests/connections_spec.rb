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
end
