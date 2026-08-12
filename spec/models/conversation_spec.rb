require "rails_helper"

RSpec.describe Conversation do
  let(:ana) { User.create!(email: "ana@example.com", name: "Ana") }
  let(:bo) { User.create!(email: "bo@example.com", name: "Bo") }

  describe ".between" do
    it "orders participants and is idempotent for either argument order" do
      one = described_class.between(ana, bo)
      two = described_class.between(bo, ana)

      expect(one).to eq(two)
      expect(one.participant_one_id).to be < one.participant_two_id
    end
  end

  describe "#other_participant / #has_participant?" do
    it "returns the counterpart and membership" do
      conversation = described_class.between(ana, bo)

      expect(conversation.other_participant(ana)).to eq(bo)
      expect(conversation.has_participant?(ana)).to be(true)
      expect(conversation.has_participant?(User.create!(email: "x@example.com"))).to be(false)
    end
  end

  describe "#unread_count_for" do
    it "counts only the counterpart's messages sent after the last read" do
      conversation = described_class.between(ana, bo)
      conversation.messages.create!(sender: bo, body: "one")
      conversation.messages.create!(sender: bo, body: "two")

      expect(conversation.unread_count_for(ana)).to eq(2)
      expect(conversation.unread_count_for(bo)).to eq(0)

      conversation.mark_read!(ana)
      expect(conversation.reload.unread_count_for(ana)).to eq(0)
    end
  end

  describe "User#can_message?" do
    it "is false between strangers and true once either side connects" do
      expect(ana.can_message?(bo)).to be(false)
      expect(ana.can_message?(ana)).to be(false)

      ana.connections.create!(connected_user: bo)
      expect(ana.can_message?(bo)).to be(true)
      expect(bo.can_message?(ana)).to be(true)
    end
  end
end
