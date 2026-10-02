require "rails_helper"

RSpec.describe EventSlots::Redeem do
  let(:operator) { create(:admin_user) }
  let(:ticket) { create(:ticket, order: create(:order, :paid)) }
  let(:slot) { EventSlot.create!(name: "Synthetic Day1 food", starts_at: Time.zone.parse("2026-10-08 06:00"), ends_at: Time.zone.parse("2026-10-08 09:00"), active: true, ticket_type_ids: [ ticket.ticket_type_id ]) }
  around { |example| travel_to(Time.zone.parse("2026-10-08 07:00")) { example.run } }

  def redeem(key = SecureRandom.uuid)
    described_class.call(slot:, ticket:, operator:, request_key: key)
  end

  it "records actor and timestamp independently from admission, with safe replay" do
    key = SecureRandom.uuid
    first = redeem(key)
    expect(redeem(key)).to eq(first)
    expect(first.admin_user).to eq(operator)
    expect(first.redeemed_at).to eq(Time.current)
    expect(ticket.reload.checked_in_at).to eq({})
    expect { redeem }.to raise_error(described_class::Rejected, /Already redeemed/)
  end

  it "does not infer entitlements" do
    slot.update!(ticket_type_ids: [ create(:ticket_type).id ])
    expect { redeem }.to raise_error(described_class::Rejected, /no entitlement/)
  end

  it "rejects drafts, closed windows, unpaid and canceled tickets" do
    slot.update!(active: false)
    expect { redeem }.to raise_error(described_class::Rejected, /draft/)
    slot.update!(active: true, ends_at: Time.current)
    expect { redeem }.to raise_error(described_class::Rejected, /closed/)
    slot.update!(ends_at: 1.hour.from_now)
    ticket.order.update!(status: :pending)
    expect { redeem }.to raise_error(described_class::Rejected, /not confirmed/)
    ticket.order.update!(status: :paid)
    ticket.update!(canceled_at: Time.current)
    expect { redeem }.to raise_error(described_class::Rejected, /not confirmed/)
  end

  it "checks ticket day validity and capacity" do
    ticket.ticket_type.update!(event_starts_on: "2026-10-09", event_ends_on: "2026-10-09")
    expect { redeem }.to raise_error(described_class::Rejected, /not valid/)
    ticket.ticket_type.update!(event_starts_on: nil, event_ends_on: nil)
    slot.update!(capacity: 1, redemption_limit: 2)
    redeem
    expect { redeem }.to raise_error(described_class::Rejected, /capacity/)
  end

  it "enforces the actual scan day for a window spanning midnight" do
    slot.update!(ends_at: Time.zone.parse("2026-10-09 09:00"))
    ticket.ticket_type.update!(event_starts_on: "2026-10-08", event_ends_on: "2026-10-08")
    travel_to(Time.zone.parse("2026-10-09 07:00"))
    expect { redeem }.to raise_error(described_class::Rejected, /not valid/)
  end

  it "allows configured repeats and authorized audited correction" do
    slot.update!(redemption_limit: 2)
    first = redeem
    redeem
    expect { described_class.correct!(redemption: first, operator: create(:admin_user, role: :desk), reason: "mistake") }.to raise_error(described_class::Rejected)
    described_class.correct!(redemption: first, operator:, reason: "Wrong meal selected")
    expect(first.reload.voided_by).to eq(operator)
    expect(first.void_reason).to eq("Wrong meal selected")
    expect { redeem(first.request_key) }.to raise_error(described_class::Rejected, /corrected/)
    expect { redeem }.to change(EventSlotRedemption, :count).by(1)
  end

  it "rolls back when audit persistence fails" do
    allow_any_instance_of(EventSlotRedemption).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
    expect { redeem }.to raise_error(ActiveRecord::RecordInvalid)
    expect(slot.redemptions.count).to eq(0)
  end
end
