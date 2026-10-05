require "rails_helper"

RSpec.describe Membership, type: :model do
  it "defaults to least privilege and prevents duplicate memberships" do
    organization = Organization.create!(name: "One", slug: "one")
    user = User.create!(email: "member@example.com")
    membership = Membership.create!(organization: organization, user: user)
    expect(membership).to be_viewer
    expect(membership.manage_events?).to be(false)
    expect(Membership.new(organization: organization, user: user, role: :owner)).not_to be_valid
  end

  it "grants event editing only to explicit management roles" do
    %w[owner admin editor].each { |role| expect(Membership.new(role: role).manage_events?).to be(true) }
    expect(Membership.new(role: "unknown")).not_to be_valid
  end
end
