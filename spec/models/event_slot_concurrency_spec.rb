require "rails_helper"

RSpec.describe "Slot concurrency", type: :model do
  self.use_transactional_tests = false

  it "serializes independent connections for capacity and duplicates" do
    operator = create(:admin_user)
    order = create(:order, :paid)
    type = create(:ticket_type)
    tickets = 2.times.map { create(:ticket, order:, ticket_type: type) }
    slot = EventSlot.create!(name: "Synthetic capacity", starts_at: Time.utc(2026, 10, 8, 6), ends_at: Time.utc(2026, 10, 8, 9), ticket_type_ids: [ type.id ], active: true, capacity: 1)
    travel_to(Time.utc(2026, 10, 8, 7)) do
      [ tickets, [ tickets.first, tickets.first ] ].each do |pair|
        EventSlotRedemption.where(event_slot: slot).delete_all
        ready = Queue.new
        start = Queue.new
        threads = pair.map do |ticket|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              ready << true
              start.pop
              begin
                EventSlots::Redeem.call(slot: EventSlot.find(slot.id), ticket: Ticket.find(ticket.id), operator:, request_key: SecureRandom.uuid)
                :success
              rescue EventSlots::Redeem::Rejected
                :rejected
              end
            end
          end
        end
        2.times { ready.pop }
        2.times { start << true }
        expect(threads.map(&:value)).to match_array([ :success, :rejected ])
        expect(slot.redemptions.count).to eq(1)
      end
    end
  ensure
    EventSlotRedemption.where(event_slot: slot).delete_all if slot
    slot&.destroy!
    tickets&.each(&:destroy!)
    order&.destroy!
    type&.destroy!
    operator&.destroy!
  end
end
