require "rails_helper"

RSpec.describe CheckinRecord do
  let(:event) { create(:event) }
  let(:ticket_type) { create(:ticket_type, event:) }
  let(:order) { create(:order, event:) }
  let(:ticket) { create(:ticket, order:, ticket_type:, event:) }

  it "logs a successful entry scan and stamps recorded_at" do
    record = event.checkin_records.create!(ticket:, direction: "entry")

    expect(record).to be_entry
    expect(record.recorded_at).to be_present
    expect(ticket.checkin_records).to include(record)
  end

  it "supports exit direction and failure reasons" do
    record = event.checkin_records.create!(ticket:, direction: "exit", successful: false, failure_reason: "already_checked_in")

    expect(record).to be_exit
    expect(record).not_to be_successful
  end

  it "orders records chronologically and filters successful scans" do
    a = event.checkin_records.create!(ticket:, recorded_at: 2.hours.ago)
    b = event.checkin_records.create!(ticket:, recorded_at: 1.hour.ago)
    failed = event.checkin_records.create!(ticket:, successful: false, recorded_at: 30.minutes.ago)

    expect(event.checkin_records.chronological.to_a).to eq([ a, b, failed ])
    expect(event.checkin_records.successful).to contain_exactly(a, b)
  end

  it "can scope a scan to a program session for per-session check-in" do
    session = event.program_sessions.create!(title: "Workshop", kind: "workshop", max_attendees: 30)

    record = event.checkin_records.create!(ticket:, program_session: session)

    expect(record.program_session).to eq(session)
  end
end
