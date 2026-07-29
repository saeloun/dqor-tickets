require "rails_helper"

RSpec.describe Account, type: :model do
  it "validates its billing identity" do
    account = build(:account, name: nil, billing_email: "invalid", country: "India")

    expect(account).not_to be_valid
    expect(account.errors).to include(:name, :billing_email, :country)
  end

  it "has many organizers" do
    account = create(:account)
    organizer = create(:organizer, account:)

    expect(account.organizers).to contain_exactly(organizer)
  end
end
