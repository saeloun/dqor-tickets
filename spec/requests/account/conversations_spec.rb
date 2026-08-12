require "rails_helper"

RSpec.describe "Account conversations", type: :request do
  def sign_in_as(user)
    get account_magic_path(
      token: Rails.application.message_verifier(:account_magic_link)
        .generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    )
  end

  let(:me) { User.create!(email: "me@example.com", name: "Me") }
  let(:friend) { User.create!(email: "friend@example.com", name: "Friend") }
  let(:stranger) { User.create!(email: "stranger@example.com", name: "Stranger") }

  it "requires sign-in" do
    post account_conversations_path, params: { attendee_id: friend.id }

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "starts a conversation with a connection" do
    me.connections.create!(connected_user: friend)
    sign_in_as(me)

    expect { post account_conversations_path, params: { attendee_id: friend.id } }
      .to change { Conversation.count }.by(1)
    expect(response).to redirect_to(account_conversation_path(Conversation.last))
  end

  it "refuses to start a conversation with someone I'm not connected to" do
    sign_in_as(me)

    expect { post account_conversations_path, params: { attendee_id: stranger.id } }
      .not_to change { Conversation.count }
    expect(response).to redirect_to(community_path)
  end

  it "shows my conversation, renders messages, and marks it read" do
    me.connections.create!(connected_user: friend)
    conversation = Conversation.between(me, friend)
    conversation.messages.create!(sender: friend, body: "hey there")
    sign_in_as(me)

    get account_conversation_path(conversation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("hey there")
    expect(conversation.reload.unread_count_for(me)).to eq(0)
  end

  it "does not let me open a conversation I'm not part of" do
    conversation = Conversation.between(friend, stranger)
    sign_in_as(me)

    get account_conversation_path(conversation)

    expect(response).to redirect_to(account_conversations_path)
  end

  it "posts a message to my conversation" do
    me.connections.create!(connected_user: friend)
    conversation = Conversation.between(me, friend)
    sign_in_as(me)

    expect { post account_conversation_messages_path(conversation), params: { message: { body: "hello" } } }
      .to change { conversation.messages.count }.by(1)
  end

  it "will not post to a conversation I'm not in" do
    conversation = Conversation.between(friend, stranger)
    sign_in_as(me)

    expect { post account_conversation_messages_path(conversation), params: { message: { body: "x" } } }
      .not_to change { Message.count }
    expect(response).to redirect_to(account_conversations_path)
  end

  it "lists only my conversations" do
    me.connections.create!(connected_user: friend)
    Conversation.between(me, friend)
    Conversation.between(friend, stranger)
    sign_in_as(me)

    get account_conversations_path

    expect(response.body).to include(friend.display_name)
    expect(response.body).not_to include(stranger.display_name)
  end
end
