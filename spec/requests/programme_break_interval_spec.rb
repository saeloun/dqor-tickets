require "rails_helper"
require Rails.root.join("db/migrate/20261007010000_correct_day_two_break_interval")

RSpec.describe "October 9 break interval correction", type: :request do
  let(:migration) { CorrectDayTwoBreakInterval.new }
  let(:starts_at) { Time.utc(2026, 10, 9, 9, 30) }
  let(:incorrect_end) { Time.utc(2026, 10, 5, 9, 40) }
  let(:correct_end) { Time.utc(2026, 10, 9, 9, 40) }

  def legacy_break(**attributes)
    Talk.create!({ id: 38, title: "Break", starts_at:, ends_at: incorrect_end, published: false, position: 10, room: "Synthetic room" }.merge(attributes)).tap do |session|
      session.update_columns(published: true)
    end
  end

  it "changes exactly the verified end field, preserves adjacent sessions, and performs no idempotent writes" do
    before = Talk.create!(id: 30, title: "Synthetic preceding talk", starts_at: starts_at - 45.minutes, ends_at: starts_at, published: true)
    after = Talk.create!(id: 37, title: "Synthetic following panel", starts_at: correct_end, ends_at: correct_end + 40.minutes, published: true)
    session = legacy_break
    original = session.attributes
    neighbors = [ before.attributes, after.attributes ]
    migration.up
    expect(session.reload.attributes).to eq(original.merge("ends_at" => correct_end))
    expect([ before.reload.attributes, after.reload.attributes ]).to eq(neighbors)
    writes = []
    observer = ->(*event) { writes << event.last[:sql] if event.last[:sql].match?(/\A(?:UPDATE|INSERT|DELETE)/i) }
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") { migration.up }
    expect(writes).to be_empty
  end

  it "updates the existing public row and invalidates its content version without filtering the feed" do
    session = legacy_break
    get "/api/public/v1/dqor/programme"
    previous = response.parsed_body
    expect(previous.fetch("sessions").find { |item| item.fetch("id") == "38" }.fetch("ends_at")).to eq("2026-10-05T15:10:00+05:30")
    migration.up
    get "/api/public/v1/dqor/programme", headers: { "If-None-Match" => response.headers.fetch("ETag") }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("content_version")).not_to eq(previous.fetch("content_version"))
    expect(response.parsed_body.fetch("sessions").find { |item| item.fetch("id") == "38" }).to include("title" => "Break", "starts_at" => "2026-10-09T15:00:00+05:30", "ends_at" => "2026-10-09T15:10:00+05:30")
    expect(session.reload).to be_published
    get schedule_path
    expect(response.body).to include("3:00 PM – 3:10 PM")
  end

  [ { title: "Edited break" }, { starts_at: Time.utc(2026, 10, 9, 9, 31) }, { ends_at: Time.utc(2026, 10, 9, 9, 45) }, { published: false } ].each do |changed|
    it "fails closed without changing data when #{changed.keys.first} differs from the verified row" do
      session = legacy_break
      session.update_columns(changed)
      original = session.attributes
      expect { migration.up }.to raise_error(RuntimeError, /preserve edits/)
      expect(session.reload.attributes).to eq(original)
    end
  end

  it "safely skips a missing target on an empty or unrelated local bootstrap" do
    other = Talk.create!(id: 39, title: "Break", starts_at:, ends_at: correct_end, published: true)
    original = other.attributes
    expect { migration.up }.not_to change(Talk, :count)
    expect(other.reload.attributes).to eq(original)
  end

  it "refuses to restore the invalid interval on rollback" do
    session = legacy_break(ends_at: correct_end)
    original = session.attributes
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration, /Keep the corrected/)
    expect(session.reload.attributes).to eq(original)
  end
end
