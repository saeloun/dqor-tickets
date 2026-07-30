require "rails_helper"

RSpec.describe Membership, type: :model do
  it "belongs to an organizer and declares the deferred user association" do
    membership = create(:membership)

    expect(membership.organizer).to be_present
    expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
  end

  it "supports every organizer role" do
    expect(described_class.roles.keys).to eq(%w[owner admin editor finance checkin_operator viewer])
  end

  it "validates one membership per organizer and user" do
    membership = create(:membership)
    duplicate = build(:membership, organizer: membership.organizer, user_id: membership.user_id)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to include("has already been taken")
  end

  it "enforces organizer and user uniqueness in the database" do
    membership = create(:membership)
    duplicate = build(:membership, organizer: membership.organizer, user_id: membership.user_id)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
