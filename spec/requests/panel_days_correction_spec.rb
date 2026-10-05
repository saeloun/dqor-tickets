require "rails_helper"
require Rails.root.join("db/migrate/20261005110000_correct_conference_panel_days")

RSpec.describe "Conference panel day correction", type: :request do
  let(:migration) { CorrectConferencePanelDays.new }
  let!(:first) { Talk.create!(id: 18, title: "Guest panel: Indian speakers", starts_at: Time.utc(2026, 10, 8, 9, 50), ends_at: Time.utc(2026, 10, 8, 10, 20), published: true, speaker_name: "Existing panel label", abstract: "Existing Day 1 abstract", room: "Main hall") }
  let!(:second) { Talk.create!(id: 37, title: "Guest panel: international speakers", starts_at: Time.utc(2026, 10, 9, 9, 40), ends_at: Time.utc(2026, 10, 9, 10, 20), published: true, abstract: "Existing Day 2 abstract") }
  let!(:other) { Talk.create!(id: 38, title: "Individual talk", starts_at: Time.utc(2026, 10, 9, 11), ends_at: Time.utc(2026, 10, 5, 12), published: true) }

  def facts
    { talks: Talk.order(:id).map(&:attributes), speakers: Speaker.order(:id).map(&:attributes), bookmarks: TalkBookmark.order(:id).map(&:attributes), types: TicketType.order(:id).map(&:attributes), coupons: Coupon.order(:id).map(&:attributes) }
  end

  def write_sql
    statements = []
    observer = ->(*event) { statements << event.last[:sql] if event.last[:sql].match?(/\A(?:UPDATE|INSERT|DELETE)/i) }
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") { yield }
    statements
  end

  it "changes only the two titles, preserves linked metadata and reverses idempotently" do
    speaker = Speaker.create!(name: "Existing speaker", status: "announced")
    second.update!(speaker: speaker)
    create(:ticket_type)
    create(:coupon)
    user = User.create!(email: "panel-reader@example.test")
    TalkBookmark.create!(user: user, talk: first)
    before = facts
    migration.up
    expected = Marshal.load(Marshal.dump(before))
    expected[:talks].find { |row| row["id"] == 18 }["title"] = "Guest panel: international speakers"
    expected[:talks].find { |row| row["id"] == 37 }["title"] = "Guest panel: Indian speakers"
    expect(facts).to eq(expected)
    expect(write_sql { migration.up }).to be_empty
    migration.down
    expect(facts).to eq(before)
    expect(write_sql { migration.down }).to be_empty
  end

  it "locks both targets before issuing either title update" do
    statements = []
    observer = ->(*event) { statements << event.last }
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") { migration.up }
    locked = statements.index { |event| event[:sql].include?("FOR UPDATE") && event[:sql].include?("ORDER BY") }
    updated = statements.index { |event| event[:sql].start_with?("UPDATE") }
    expect(locked).to be < updated
    expect(statements.fetch(locked)[:binds].map(&:value_for_database)).to include(18, 37)
  end

  [ :title, :start, :end, :publication, :partial, :missing, :duplicate ].each do |edit|
    it "refuses #{edit} changes without any writes" do
      case edit
      when :title then first.update!(title: "Organizer edit")
      when :start then first.update!(starts_at: first.starts_at + 1.minute)
      when :end then second.update!(ends_at: second.ends_at + 1.minute)
      when :publication then second.update!(published: false)
      when :partial then first.update!(title: "Guest panel: international speakers")
      when :missing then second.destroy!
      when :duplicate then Talk.create!(id: 100, title: first.title, starts_at: first.starts_at, published: true)
      end
      before = facts
      writes = write_sql { expect { migration.up }.to raise_error(RuntimeError, /inspect before migration/) }
      expect(writes).to be_empty
      expect(facts).to eq(before)
    end
  end

  it "does not silently skip missing panels in a populated catalogue" do
    first.destroy!
    second.destroy!
    before = facts
    expect { migration.up }.to raise_error(RuntimeError, /inspect before migration/)
    expect(facts).to eq(before)
  end

  it "does nothing in an empty fresh catalogue in either direction" do
    Talk.delete_all
    expect(write_sql { migration.up; migration.down }).to be_empty
  end

  it "refuses rollback after a newer organizer edit" do
    migration.up
    second.update!(title: "New organizer title")
    before = facts
    expect { migration.down }.to raise_error(RuntimeError, /inspect before migration/)
    expect(facts).to eq(before)
  end

  it "rolls back the first title if the second write fails" do
    relation = CorrectConferencePanelDays::ProgrammeItem.where(id: 37)
    allow(CorrectConferencePanelDays::ProgrammeItem).to receive(:where).and_call_original
    allow(CorrectConferencePanelDays::ProgrammeItem).to receive(:where).with(id: 37).and_return(relation)
    allow(relation).to receive(:update_all).and_raise("Synthetic second write failure")
    before = facts
    expect { migration.up }.to raise_error(RuntimeError, "Synthetic second write failure")
    expect(facts).to eq(before)
  end

  it "updates schedule, details, public JSON and bookmarked ICS without changing IDs or time slots" do
    get "/api/public/v1/dqor/programme"
    previous_etag = response.headers.fetch("ETag")
    previous_json = response.parsed_body
    get calendar_path
    conference_calendar = response.body
    user = User.create!(email: "panel-reader@example.test")
    [ first, second ].each { |talk| TalkBookmark.create!(user: user, talk: talk) }
    migration.up
    get "/api/public/v1/dqor/programme", headers: { "If-None-Match" => previous_etag }
    expect(response).to have_http_status(:ok)
    expect(response.headers.fetch("ETag")).not_to eq(previous_etag)
    expected = previous_json.deep_dup
    expected["sessions"].find { |row| row["id"] == "18" }["title"] = "Guest panel: international speakers"
    expected["sessions"].find { |row| row["id"] == "37" }["title"] = "Guest panel: Indian speakers"
    expect(response.parsed_body.except("content_version")).to eq(expected.except("content_version"))
    expect(response.parsed_body["content_version"]).not_to eq(previous_json["content_version"])
    current_etag = response.headers.fetch("ETag")
    get "/api/public/v1/dqor/programme", headers: { "If-None-Match" => current_etag }
    expect(response).to have_http_status(:not_modified)
    get schedule_path
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('a[href="/talks/18"]').text).to include("Guest panel: international speakers")
    expect(document.at_css('a[href="/talks/37"]').text).to include("Guest panel: Indian speakers")
    expect(response.body).to include("3:20 PM – 3:50 PM", "3:10 PM – 3:50 PM")
    [ first, second ].each do |talk|
      get talk_path(talk)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(talk.reload.title, talk.abstract)
    end
    get calendar_path
    expect(response.body).to eq(conference_calendar)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
    get account_calendar_path
    expect(response).to have_http_status(:ok)
    events = response.body.split("BEGIN:VEVENT").drop(1)
    expect(events.find { |event| event.include?("UID:talk-18@") }).to include("SUMMARY:Guest panel: international speakers", "DTSTART:20261008T095000Z", "DTEND:20261008T102000Z")
    expect(events.find { |event| event.include?("UID:talk-37@") }).to include("SUMMARY:Guest panel: Indian speakers", "DTSTART:20261009T094000Z", "DTEND:20261009T102000Z")
  end
end
