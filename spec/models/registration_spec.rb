require "rails_helper"

RSpec.describe Registration, type: :model do
  it "belongs to event and user with an optional ticket" do
    registration = create(:registration)

    expect(registration.event).to be_present
    expect(registration.user).to be_present
    expect(registration.ticket).to be_nil
  end

  it "enforces one registration per user and event" do
    registration = create(:registration)
    duplicate = build(:registration, event: registration.event, user: registration.user)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to include("has already been taken")

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "supports every attendance and payment state" do
    expect(described_class.attendance_states.keys).to eq(%w[interested going waitlisted pending_approval cancelled])
    expect(described_class.payment_states.keys).to eq(%w[not_required awaiting_payment authorized captured refunded released])
  end

  it "knows when a registration grants attendance access" do
    expect(build(:registration, attendance_state: "going", payment_state: "not_required")).to be_attending
    expect(build(:registration, attendance_state: "going", payment_state: "captured")).to be_attending
    expect(build(:registration, attendance_state: "interested", payment_state: "not_required")).not_to be_attending
    expect(build(:registration, attendance_state: "going", payment_state: "refunded")).not_to be_attending
  end

  it "excludes pending_approval and waitlisted from public guests" do
    going = create(:registration, attendance_state: "going")
    interested = create(:registration, attendance_state: "interested")
    create(:registration, attendance_state: "waitlisted")
    create(:registration, attendance_state: "pending_approval")

    expect(described_class.public_guests).to contain_exactly(going, interested)
  end
end
