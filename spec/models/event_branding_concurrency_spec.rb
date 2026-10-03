require "rails_helper"

RSpec.describe "Event branding concurrency", type: :model do
  self.use_transactional_tests = false

  before do
    @setting = EventBrandingSetting.current
    @operator = create(:admin_user)
  end

  after do
    @setting.reload.destroy!
    @operator.destroy!
  end

  it "commits only one of two concurrent writes based on the same saved revision" do
    ready = Queue.new
    start = Queue.new
    version = @setting.lock_version
    threads = %w[#123456 #654321].map do |accent|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          setting = EventBrandingSetting.find(@setting.id)
          values = setting.draft.except("assets").merge("accent" => accent)
          ready << true
          start.pop
          begin
            setting.save_draft!(values: values, uploads: {}, removals: [], expected_version: version, actor: @operator)
            :saved
          rescue EventBrandingSetting::StaleDraft
            :stale
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    expect(threads.map(&:value)).to match_array([ :saved, :stale ])
    expect(@setting.reload.lock_version).to eq(version + 1)
  end
end
