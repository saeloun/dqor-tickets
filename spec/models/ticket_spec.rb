require "rails_helper"

RSpec.describe Ticket, type: :model do
  it "generates a unique 24-character base58 secret" do
    ticket = create(:ticket)

    expect(ticket.secret).to match(/\A[1-9A-HJ-NP-Za-km-z]{24}\z/)
  end

  it "records separate per-day check-ins" do
    ticket = create(:ticket)

    first = ticket.check_in!(Date.new(2026, 10, 8))
    second = ticket.check_in!(Date.new(2026, 10, 9))

    expect(ticket.reload.checked_in_at).to eq("2026-10-08" => first, "2026-10-09" => second)
  end

  it "raises with the prior timestamp on a duplicate check-in" do
    ticket = create(:ticket)
    checked_in_at = ticket.check_in!(Date.new(2026, 10, 8))

    expect { ticket.check_in!(Date.new(2026, 10, 8)) }
      .to raise_error(described_class::AlreadyCheckedIn) { |error| expect(error.checked_in_at).to eq(checked_in_at) }
  end

  it "rejects a canceled ticket" do
    ticket = create(:ticket, canceled_at: Time.current)

    expect { ticket.check_in!(Date.new(2026, 10, 8)) }.to raise_error(described_class::Canceled)
  end
end
