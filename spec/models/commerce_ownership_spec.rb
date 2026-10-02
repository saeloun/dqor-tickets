require "rails_helper"

RSpec.describe "Commerce ownership constraints" do
  let!(:organization) { Organization.create!(name: "One", slug: "one") }
  let!(:event) { organization.events.create!(title: "One", slug: "one") }
  let!(:other_event) { organization.events.create!(title: "Two", slug: "two") }
  let!(:type) { create(:ticket_type, event_id: event.id, hidden: true, active: false) }
  let!(:order) { create(:order, event_id: event.id) }
  let!(:ticket) { create(:ticket, event_id: event.id, order: order, ticket_type: type) }
  let!(:legacy) { create(:ticket) }

  def database_write(&block)
    ApplicationRecord.transaction(requires_new: true, &block)
  end

  it "leaves legacy ownership unset and legacy operations valid" do
    expect([ legacy.event_id, legacy.order.event_id, legacy.ticket_type.event_id ]).to all(be_nil)
    legacy.update!(attendee_name: "Legacy still works")
    expect(legacy.reload.ownership_key).to eq(0)
  end

  it "rejects cross-event order and ticket-type relationships even without model validations" do
    other_order = create(:order, event_id: other_event.id)
    other_type = create(:ticket_type, event_id: other_event.id, active: false, hidden: true)
    expect { database_write { ticket.update_columns(order_id: other_order.id) } }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect { database_write { ticket.update_columns(ticket_type_id: other_type.id) } }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "rejects legacy/null ownership mixed with tenant ownership in either direction" do
    expect { database_write { ticket.update_columns(event_id: nil) } }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect { database_write { legacy.update_columns(order_id: order.id) } }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect { database_write { legacy.update_columns(ticket_type_id: type.id) } }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect { database_write { ticket.reload.update_columns(order_id: legacy.reload.order_id) } }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "prevents reparenting an order or type that has tickets" do
    expect { database_write { order.update_columns(event_id: other_event.id) } }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect { database_write { type.update_columns(event_id: other_event.id) } }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "keeps staged types hidden and inactive even for direct database writes" do
    expect { database_write { type.update_columns(active: true) } }.to raise_error(ActiveRecord::StatementInvalid)
    expect { database_write { type.update_columns(hidden: false) } }.to raise_error(ActiveRecord::StatementInvalid)
  end
end
