require "rails_helper"

RSpec.describe Connection do
  let(:person) { User.create!(email: "a@example.com") }
  let(:other) { User.create!(email: "b@example.com") }

  it "connects two users" do
    expect(person.connections.create(connected_user: other)).to be_persisted
  end

  it "prevents duplicate connections" do
    person.connections.create!(connected_user: other)

    expect(person.connections.build(connected_user: other)).not_to be_valid
  end

  it "prevents connecting to yourself" do
    expect(person.connections.build(connected_user: person)).not_to be_valid
  end
end
