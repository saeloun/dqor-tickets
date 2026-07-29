require "rails_helper"

RSpec.describe "Conference schedule" do
  let(:event) { create(:event) }

  it "builds tracks, rooms, speakers and sessions scoped to an event" do
    track = event.tracks.create!(name: "Main")
    room = event.rooms.create!(name: "Auditorium")
    speaker = event.speakers.create!(name: "Ada Lovelace", github: "@ada")
    session = event.program_sessions.create!(
      title: "Keynote", kind: "keynote", track:, room:,
      starts_at: 1.hour.from_now, ends_at: 2.hours.from_now
    )
    session.program_session_speakers.create!(speaker:, role: "speaker")

    expect(session.speakers).to include(speaker)
    expect(track.program_sessions).to include(session)
    expect(event.program_sessions).to include(session)
    expect(session).to be_confirmed
  end

  it "normalizes a speaker github handle to a bare username" do
    speaker = event.speakers.create!(name: "Grace Hopper", github: "@grace")

    expect(speaker.github).to eq("grace")
  end

  it "requires a session title and orders its times" do
    expect(event.program_sessions.new(title: nil)).not_to be_valid

    out_of_order = event.program_sessions.new(title: "T", starts_at: 2.hours.from_now, ends_at: 1.hour.from_now)
    expect(out_of_order).not_to be_valid
    expect(out_of_order.errors[:ends_at]).to be_present
  end

  it "allows every session kind including a break slot" do
    %w[talk keynote workshop panel lightning break social].each do |kind|
      expect(event.program_sessions.create!(title: "S", kind: kind)).to be_persisted
    end
  end

  it "enforces one assignment per speaker per session" do
    speaker = event.speakers.create!(name: "Alan Turing")
    session = event.program_sessions.create!(title: "Talk")
    session.program_session_speakers.create!(speaker:)

    dup = session.program_session_speakers.new(speaker:)
    expect(dup).not_to be_valid
  end

  it "toggles the conference module via event settings" do
    expect(event.conference_module?).to be(false)

    event.update!(settings: { "conference_module" => true })

    expect(event.reload.conference_module?).to be(true)
  end
end
