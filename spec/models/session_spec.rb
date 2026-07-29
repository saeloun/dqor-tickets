require "rails_helper"

RSpec.describe Session, type: :model do
  it "belongs to either an admin user or a user" do
    admin_session = create(:session)
    user_session = create(:session, user: create(:user), admin_user: nil)

    expect(admin_session.account).to eq(admin_session.admin_user)
    expect(user_session.account).to eq(user_session.user)
  end

  it "requires an account" do
    session = build(:session, admin_user: nil, user: nil)

    expect(session).not_to be_valid
    expect(session.errors[:base]).to include("must belong to a user or admin user")
  end
end
