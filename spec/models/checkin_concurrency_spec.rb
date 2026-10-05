require "rails_helper"

RSpec.describe "check-in concurrency", type: :model do
  self.use_transactional_tests = false

  before do
    @operator = create(:admin_user)
    @order = create(:order, :paid)
    @type = create(:ticket_type)
    @ticket = create(:ticket, order: @order, ticket_type: @type)
  end

  after do
    CheckinAudit.where(ticket_id: @ticket.id).delete_all
    @ticket.destroy!
    @order.destroy!
    @type.destroy!
    @operator.destroy!
  end

  it "allows only one success when a scanner and batch race on separate database connections" do
    ready = Queue.new
    start = Queue.new
    connections = Queue.new
    threads = %w[scanner batch].map do |source|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connections << connection.object_id
          ready << true
          start.pop
          Checkins::Record.call(ticket: Ticket.find(@ticket.id), date: Date.new(2026, 10, 8), operator: @operator, source:)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)
    expect(results.pluck(:state)).to match_array(%w[success warning])
    expect(2.times.map { connections.pop }.uniq.size).to eq(2)
    expect(@ticket.reload.checked_in_at.keys).to eq([ "2026-10-08" ])
    expect(CheckinAudit.where(ticket: @ticket).pluck(:outcome)).to match_array(%w[success duplicate])
  end
end
