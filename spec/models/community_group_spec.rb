require "rails_helper"

RSpec.describe CommunityGroup do
  let!(:organization) { Organization.create!(name: "One", slug: "one") }
  let!(:other_organization) { Organization.create!(name: "Two", slug: "two") }
  let!(:group) { organization.community_groups.create!(name: "Ruby", slug: "ruby") }

  it "bounds public facts and requires a real IANA timezone" do
    expect(organization.community_groups.new(name: "Ruby", slug: "invalid", timezone: "Private/Guess")).not_to be_valid
    expect(organization.community_groups.new(name: "x" * 121, slug: "long")).not_to be_valid
    expect(organization.community_groups.new(name: "Ruby", slug: "description", description: "x" * 2001)).not_to be_valid
    expect(group.update(status: :published)).to be(false)
  end

  it "allows the same community slug in distinct organizations" do
    expect(other_organization.community_groups.create!(name: "Other Ruby", slug: "ruby").slug).to eq(group.slug)
    expect(organization.community_groups.new(name: "Duplicate", slug: "ruby")).not_to be_valid
  end

  it "rejects cross-tenant association both in the model and database" do
    event = other_organization.events.create!(title: "Other event", slug: "other")
    event.community_group = group
    expect(event).not_to be_valid
    expect(event.errors[:community_group]).to include("must belong to this organization")
    expect do
      Event.transaction(requires_new: true) { event.update_column(:community_group_id, group.id) }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(event.reload.community_group_id).to be_nil
  end

  it "retains existing event records and blocks deletion of a populated community" do
    event = organization.events.create!(title: "Retained", slug: "retained", community_group: group)
    expect { group.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    expect(event.reload.community_group_id).to eq(group.id)
  end
end

RSpec.describe CommunityGroups::PublicCatalog do
  it "bounds scalar pagination and rejects structured or malformed inputs" do
    { nil => 1, [] => 1, {} => 1, "no" => 1, "1x" => 1, "-1" => 1, "0" => 1, "2" => 2, "2000" => 1000, "9" * 10000 => 1000 }.each do |value, expected|
      expect(described_class.page_number(value)).to eq(expected)
    end
  end
end
