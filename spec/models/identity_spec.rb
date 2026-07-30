require "rails_helper"

RSpec.describe Identity, type: :model do
  it "belongs to a user and enforces provider/uid uniqueness" do
    identity = create(:identity)
    duplicate = build(:identity, provider: identity.provider, uid: identity.uid)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:uid]).to include("has already been taken")
  end
end
