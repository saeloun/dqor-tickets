require "rails_helper"

RSpec.describe PersonalScheduleEntry do
  let(:event) { create(:event) }
  let(:registration) { create(:registration, event:) }

  def session(starts_at:, ends_at:, title: "S")
    event.program_sessions.create!(title:, starts_at:, ends_at:)
  end

  it "lets an attendee add a session to their agenda once" do
    talk = session(starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)

    registration.personal_schedule_entries.create!(program_session: talk)

    expect(registration.program_sessions).to include(talk)
    dup = registration.personal_schedule_entries.new(program_session: talk)
    expect(dup).not_to be_valid
  end

  it "rejects a session from a different event" do
    other_event = create(:event, slug: "other-2026")
    foreign = other_event.program_sessions.create!(title: "Foreign", starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)

    entry = registration.personal_schedule_entries.new(program_session: foreign)

    expect(entry).not_to be_valid
    expect(entry.errors[:program_session]).to be_present
  end

  it "detects overlapping sessions in the agenda" do
    a = session(starts_at: Time.utc(2026, 10, 8, 10), ends_at: Time.utc(2026, 10, 8, 11))
    b = session(starts_at: Time.utc(2026, 10, 8, 10, 30), ends_at: Time.utc(2026, 10, 8, 11, 30))
    c = session(starts_at: Time.utc(2026, 10, 8, 12), ends_at: Time.utc(2026, 10, 8, 13))

    [ a, b, c ].each { |s| registration.personal_schedule_entries.create!(program_session: s) }

    conflicts = registration.agenda_conflicts
    expect(conflicts.size).to eq(1)
    expect(conflicts.first).to contain_exactly(a, b)
  end
end
