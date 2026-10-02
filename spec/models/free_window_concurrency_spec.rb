require "rails_helper"
require "timeout"

RSpec.describe "Registration window locking", type: :model do
  self.use_transactional_tests = false

  it "serializes final capacity and rechecks a newly closed window after waiting for the event lock" do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_registration_windows_enabled).and_return(true)
    org = Organization.create!(name: "Window race", slug: "window-race")
    event = org.events.create!(title: "Free", slug: "free", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now)
    type = create(:ticket_type, event_id: event.id, hidden: true, active: false, price_paise: 0, capacity: 1, free_published_at: Time.current)
    users = 2.times.map { create(:user_for_free_pilot) }
    owner = create(:user_for_free_pilot)
    membership = Membership.create!(organization: org, user: owner, role: :owner)
    access = { user: owner, organization_id: org.id, event_id: event.id, ticket_type_id: type.id }
    window = FreeEvents::Windows.change(**access, action: "save", revision: 0)
    FreeEvents::Windows.change(**access, action: "publish", revision: window.lock_version)
    ready, start = Queue.new, Queue.new
    workers = users.map do |user|
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
    expect(workers.map(&:value).count(:full)).to eq(1)
    expect(Ticket.where(event_id: event.id).count).to eq(1)
    Ticket.where(event_id: event.id).delete_all
    Order.where(event_id: event.id).delete_all

    waiter = nil
    waiting_pid = Queue.new
    Event.transaction do
      event.lock!
      waiter = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          waiting_pid << connection.select_value("SELECT pg_backend_pid()")
          begin
            FreeEvents::Register.call(user: users.first, event_id: event.id, ticket_type_id: type.id)
          rescue FreeEvents::Register::Unavailable => error
            error.message
          end
        end
      end
      pid = Integer(waiting_pid.pop)
      Timeout.timeout(5) do
        loop do
          break if ActiveRecord::Base.connection.select_value("SELECT cardinality(pg_blocking_pids(#{pid}))").positive?
          sleep 0.01
        end
      end
      window.reload
      window = FreeEvents::Windows.change(**access, action: "save", revision: window.lock_version, closes_local: 1.minute.ago.in_time_zone(event.timezone).strftime("%Y-%m-%dT%H:%M"))
      FreeEvents::Windows.change(**access, action: "publish", revision: window.lock_version)
    end
    expect(waiter.value).to include("closed")
    expect(Order.where(event_id: event.id)).to be_empty
  ensure
    workers&.each(&:join)
    waiter&.join
    if event
      Ticket.where(event_id: event.id).delete_all
      Order.where(event_id: event.id).delete_all
      FreeEvents::RegistrationWindow.where(event_id: event.id).delete_all
    end
    membership&.destroy!
    type&.destroy!
    event&.destroy!
    org&.reload&.destroy!
    users&.each(&:destroy!)
    owner&.destroy!
  end
end
