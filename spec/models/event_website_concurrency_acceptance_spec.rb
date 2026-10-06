require "rails_helper"

RSpec.describe "Event website concurrency acceptance", type: :model do
  self.use_transactional_tests = false

  before do
    @organization = Organization.create!(name: "Synthetic Concurrent Community", slug: "website-concurrent")
    @owner = create(:user_for_free_pilot)
    @membership = Membership.create!(organization: @organization, user: @owner, role: :owner)
    @event = @organization.events.create!(title: "Concurrent Website", slug: "concurrent")
    @setting = EventWebsiteSetting.create!(event: @event, draft: EventWebsites::Configuration.defaults.to_h)
  end

  after do
    @setting&.reload&.destroy!
    @event&.destroy!
    @membership&.destroy!
    @owner&.destroy!
    @organization&.reload&.destroy!
  end

  def values(summary)
    @setting.reload.draft.except("assets").merge("summary" => summary)
  end

  def save(summary)
    @setting.save_draft!(values: values(summary), uploads: {}, removals: [], expected_version: @setting.lock_version, actor: @owner)
  end

  def race(*operations)
    version = @setting.reload.lock_version
    ready = Queue.new
    start = Queue.new
    connections = Queue.new
    threads = operations.map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.execute("SET lock_timeout = '5s'")
          record = EventWebsiteSetting.find(@setting.id)
          connections << connection.object_id
          ready << true
          start.pop
          begin
            operation.call(record, version)
          rescue EventWebsiteSetting::StaleDraft
            :stale
          ensure
            connection.execute("RESET lock_timeout")
          end
        end
      end
    end
    operations.size.times { ready.pop }
    operations.size.times { start << true }
    results = threads.map(&:value)
    expect(operations.size.times.map { connections.pop }.uniq.size).to eq(operations.size)
    expect(@setting.reload.lock_version).to eq(version + 1)
    results
  end

  it "retains only one concurrent saved draft based on the same revision" do
    originals = %w[First Second].map { |summary| values(summary) }
    results = race(*originals.map do |draft|
      ->(record, version) do
        record.save_draft!(values: draft, uploads: {}, removals: [], expected_version: version, actor: @owner)
        :saved
      end
    end)
    expect(results).to match_array([ :saved, :stale ])
    expect(@setting.reload.draft.fetch("summary")).to be_in(%w[First Second])
    expect(@setting.published).to be_nil
  end

  it "rejects a concurrent save or publication instead of publishing an unreviewed later draft" do
    save("Original publication")
    @setting.publish!(expected_version: @setting.reload.lock_version, actor: @owner)
    save("Reviewed draft")
    later = values("Later private draft")
    results = race(
      ->(record, version) { record.save_draft!(values: later, uploads: {}, removals: [], expected_version: version, actor: @owner); :saved },
      ->(record, version) { record.publish!(expected_version: version, actor: @owner); :published }
    )
    expect(results.count(:stale)).to eq(1)
    @setting.reload
    if results.include?(:published)
      expect(@setting.published.fetch("summary")).to eq("Reviewed draft")
      expect(@setting.draft.fetch("summary")).to eq("Reviewed draft")
    else
      expect(@setting.published.fetch("summary")).to eq("Original publication")
      expect(@setting.draft.fetch("summary")).to eq("Later private draft")
    end
  end

  it "commits only one concurrent publication or restoration without losing the saved draft" do
    save("First publication")
    @setting.publish!(expected_version: @setting.reload.lock_version, actor: @owner)
    save("Second publication")
    @setting.publish!(expected_version: @setting.reload.lock_version, actor: @owner)
    save("Next private draft")
    original_draft = @setting.reload.draft.deep_dup
    results = race(
      ->(record, version) { record.publish!(expected_version: version, actor: @owner); :published },
      ->(record, version) { record.restore!(expected_version: version, actor: @owner); :restored }
    )
    expect(results.count(:stale)).to eq(1)
    @setting.reload
    expect(@setting.draft).to eq(original_draft)
    expect(@setting.published.fetch("summary")).to eq(results.include?(:published) ? "Next private draft" : "First publication")
    expect(@setting.previous_published.fetch("summary")).to eq("Second publication")
  end
end
