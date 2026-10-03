require "rails_helper"

RSpec.describe "Operations persistence" do
  let!(:org) { Organization.create!(name: "Org", slug: "ops-model") }
  let!(:event) { org.events.create!(title: "One", slug: "one") }
  let!(:other) { org.events.create!(title: "Two", slug: "two") }
  let!(:contact) { Operations::BusinessContact.create!(event: event, name: "Partner") }
  let!(:deal) { Operations::SponsorDeal.create!(event: event, business_contact: contact, title: "Gold", stage: "committed", contribution: "cash", amount_paise: 1000) }
  let!(:user) { User.create!(email: "ops-model@example.com") }

  it "rejects related records belonging to a different event" do
    expect(Operations::SponsorDeal.new(event: other, business_contact: contact, title: "Bad", stage: "pledged", contribution: "cash", amount_paise: 10)).not_to be_valid
    expect(Operations::VendorEngagement.new(event: other, business_contact: contact, title: "Bad", amount_paise: 10)).not_to be_valid
    expect(Operations::FulfillmentTask.new(event: other, sponsor_deal: deal, title: "Bad")).not_to be_valid
    expect(Operations::ManualEntry.new(event: other, sponsor_deal: deal, kind: "receipt", amount_paise: 10, occurred_on: Date.current, reference: "Bad")).not_to be_valid
  end

  it "rolls back cash if its audit cannot be saved and makes saved entries immutable" do
    entry = Operations::ManualEntry.new(event: event, sponsor_deal: deal, kind: "receipt", amount_paise: 500, occurred_on: Date.current, reference: "Test")
    allow(Operations::AuditLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    expect { Operations::RecordEntry.call(entry, user: user) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Operations::ManualEntry.count).to eq(0)
    allow(Operations::AuditLog).to receive(:create!).and_call_original
    expect(Operations::RecordEntry.call(entry, user: user)).to be(true)
    expect { entry.update!(amount_paise: 1) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { entry.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { Operations::AuditLog.last.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
