require "rails_helper"

RSpec.describe Talk, "published intervals" do
  let(:starts_at) { Time.utc(2026, 10, 9, 9, 30) }

  it "rejects a published end before or equal to its known start" do
    [ starts_at - 4.days, starts_at ].each do |ends_at|
      session = described_class.new(title: "Synthetic published session", starts_at:, ends_at:, published: true)
      expect(session).not_to be_valid
      expect(session.errors[:ends_at]).to include("must be after start time for a published session")
    end
  end

  it "allows an invalid unpublished draft but refuses publication until its interval is corrected" do
    draft = described_class.create!(title: "Synthetic draft", starts_at:, ends_at: starts_at - 4.days, published: false)
    expect(draft.update(published: true)).to be(false)
    expect(draft.reload).not_to be_published
    expect(draft.update(ends_at: starts_at + 10.minutes, published: true)).to be(true)
  end

  it "accepts valid known intervals and keeps all existing TBA combinations" do
    [ [ starts_at, starts_at + 10.minutes ], [ nil, nil ], [ starts_at, nil ], [ nil, starts_at ] ].each do |start, finish|
      expect(described_class.new(title: "Synthetic session", starts_at: start, ends_at: finish, published: true)).to be_valid
    end
  end

  it "rejects edits that reverse an already published interval" do
    session = described_class.create!(title: "Synthetic session", starts_at:, ends_at: starts_at + 10.minutes, published: true)
    expect(session.update(ends_at: starts_at - 1.minute)).to be(false)
    expect(session.reload.ends_at).to eq(starts_at + 10.minutes)
  end
end
