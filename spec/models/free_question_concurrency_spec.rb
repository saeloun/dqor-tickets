require "rails_helper"

RSpec.describe "Free question registration concurrency", type: :model do
  self.use_transactional_tests = false

  it "serializes duplicate answers and capacity with immutable snapshots on independent connections" do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_pilot_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:free_event_questions_enabled).and_return(true)
    org = Organization.create!(name: "Concurrent questions", slug: "concurrent-questions")
    event = org.events.create!(title: "Free", slug: "free", status: :published, starts_at: 1.hour.ago, ends_at: 1.day.from_now)
    type = create(:ticket_type, event_id: event.id, hidden: true, active: false, price_paise: 0, capacity: 1, free_published_at: Time.current)
    users = 2.times.map { create(:user_for_free_pilot) }
    owner = create(:user_for_free_pilot)
    membership = Membership.create!(organization: org, user: owner, role: :owner)
    access = { user: owner, organization_id: org.id, event_id: event.id, ticket_type_id: type.id }
    ready, start = Queue.new, Queue.new
    editors = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            FreeEvents::Questions::Editor.change(**access, action: "add", revision: 0, fields: { "label" => "Topic", "type" => "short_text", "required" => "1" })
          rescue FreeEvents::Questions::Invalid
            :stale
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = editors.map(&:value)
    expect(results.count(:stale)).to eq(1)
    form = FreeEvents::Form.find_by!(ticket_type: type)
    expect(form.lock_version).to eq(1)
    expect(form.draft_questions.length).to eq(1)
    version = FreeEvents::Questions::Editor.change(**access, action: "publish", revision: form.lock_version)
    id = version.questions.first["id"]
    [ users, [ users.first, users.first ] ].each do |pair|
      FreeEvents::Response.where(event_id: event.id).delete_all
      Ticket.where(event_id: event.id).delete_all
      Order.where(event_id: event.id).delete_all
      ready, start = Queue.new, Queue.new
      threads = pair.each_with_index.map do |user, index|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            begin
              FreeEvents::Register.call(user: user, event_id: event.id, ticket_type_id: type.id, form_version_id: version.id, registration_answers: { id => "answer #{index}" }).id
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
      response = FreeEvents::Response.where(event_id: event.id).sole
      expect(response.form_version_id).to eq(version.id)
      expect([ "answer 0", "answer 1" ]).to include(response.answers[id])
      pair.uniq.size == 1 ? expect(results.uniq.size).to(eq(1)) : expect(results).to(include(:full))
    end
  ensure
    if event
      FreeEvents::Response.where(event_id: event.id).delete_all
      FreeEvents::FormVersion.where(event_id: event.id).delete_all
      FreeEvents::Form.where(event_id: event.id).delete_all
      Ticket.where(event_id: event.id).delete_all
      Order.where(event_id: event.id).delete_all
    end
    membership&.destroy!
    type&.destroy!
    event&.destroy!
    org&.reload&.destroy!
    users&.each(&:destroy!)
    owner&.destroy!
  end
end
