require "rails_helper"

RSpec.describe "Public event catalog publication concurrency", type: :model do
  self.use_transactional_tests = false

  it "keeps a selected page and its total consistent when publication changes after the page read" do
    organization = Organization.create!(name: "Synthetic concurrent hosts", slug: "synthetic-concurrent-hosts")
    events = 24.times.map do |index|
      organization.events.create!(title: "Synthetic concurrent #{index}", slug: "concurrent-#{index}", status: :published,
        starts_at: Time.utc(2000, 1, 1) + index.hours, ends_at: Time.utc(2000, 1, 1, 1) + index.hours)
    end
    original_total = Event.published.count
    withdrawn = false
    listener = lambda do |_name, _started, _finished, _id, payload|
      next unless !withdrawn && payload[:sql].match?(/SELECT.*FROM "events".*LIMIT/)
      withdrawn = true
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { events.last.update_columns(status: "draft") }
      end.value
    end
    snapshot = ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { PublicEvents::Snapshot.index("1") }
    expect(withdrawn).to be(true)
    expect(snapshot.fetch(:events).size).to eq(24)
    expect(Event.published.count).to eq(original_total - 1)
    expect(snapshot.fetch(:pagination).fetch(:total)).to eq(original_total)
  ensure
    events&.each(&:destroy!)
    organization&.reload&.destroy!
  end
end
