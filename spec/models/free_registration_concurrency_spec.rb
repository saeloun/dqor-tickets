require "rails_helper"

RSpec.describe "Free registration concurrency", type: :model do
  self.use_transactional_tests = false

  it "serializes capacity and retry requests across independent connections" do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
    organization = Organization.create!(name: "Concurrent demo", slug: "concurrent-demo")
    event = organization.events.create!(title: "Free", slug: "free", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now)
    type = create(:ticket_type, event_id: event.id, hidden: true, active: false, price_paise: 0, capacity: 1, free_published_at: Time.current)
    users = 2.times.map { create(:user_for_free_pilot) }
    [ users, [ users.first, users.first ] ].each do |pair|
      Ticket.where(event_id: event.id).delete_all
      Order.where(event_id: event.id).delete_all
      ready = Queue.new
      start = Queue.new
      threads = pair.map do |user|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            begin
              FreeEvents::Register.call(user: user, event_id: event.id, ticket_type_id: type.id).id
            rescue FreeEvents::Register::Unavailable
              :full
            end
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      results = threads.map(&:value)
      expect(Ticket.where(event_id: event.id).count).to eq(1)
      expect(Order.where(event_id: event.id).count).to eq(1)
      if pair.uniq.size == 1
        expect(results.uniq.size).to eq(1)
      else
        expect(results).to include(:full)
      end
    end
  ensure
    Ticket.where(event_id: event.id).delete_all if event
    Order.where(event_id: event.id).delete_all if event
    type&.destroy!
    event&.destroy!
    organization&.reload&.destroy!
    users&.each(&:destroy!)
  end
end
