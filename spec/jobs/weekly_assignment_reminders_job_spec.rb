require "rails_helper"

RSpec.describe WeeklyAssignmentRemindersJob, type: :job do
  around do |example|
    travel_to(Time.find_zone!(Conference::ZONE).local(2026, 10, 11, 23, 59, 59)) { example.run }
  end

  it "reminds buyers who still have an unassigned ticket" do
    order = create(:order, :paid)
    create(:ticket, order:, attendee_name: nil, attendee_email: nil, assigned_at: nil)

    expect { described_class.perform_now }
      .to have_enqueued_mail(OrderMailer, :order_link).with(params: { weekly_assignment_reminder: true }, args: [ order ])
  end

  it "reminds assigned attendees who are missing details" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:, assigned_at: Time.current, tshirt_size: nil)

    expect { described_class.perform_now }
      .to have_enqueued_mail(OrderMailer, :complete_details).with(params: { weekly_assignment_reminder: true }, args: [ ticket ])
  end

  it "sends nothing for a fully assigned order with complete details" do
    order = create(:order, :paid)
    create(:ticket, order:, assigned_at: Time.current, tshirt_size: "M")

    expect { described_class.perform_now }.not_to change { enqueued_jobs.size }
  end

  it "ignores unpaid orders" do
    order = create(:order)
    create(:ticket, order:, attendee_name: nil, attendee_email: nil, assigned_at: nil)

    expect { described_class.perform_now }.not_to change { enqueued_jobs.size }
  end

  it "reminds a buyer only once even with several unassigned tickets" do
    order = create(:order, :paid)
    create(:ticket, order:, attendee_name: nil, attendee_email: nil, assigned_at: nil)
    create(:ticket, order:, attendee_name: nil, attendee_email: nil, assigned_at: nil)

    expect { described_class.perform_now }
      .to have_enqueued_mail(OrderMailer, :order_link).with(params: { weekly_assignment_reminder: true }, args: [ order ]).once
  end
  it "ignores canceled tickets for both reminder types" do
    order = create(:order, :paid)
    create(:ticket, order:, attendee_name: nil, attendee_email: nil, assigned_at: nil, canceled_at: Time.current)
    create(:ticket, order:, assigned_at: Time.current, tshirt_size: nil, canceled_at: Time.current)
    expect { described_class.perform_now }.not_to change { enqueued_jobs.size }
  end

  it "ignores assigned attendees on unpaid orders" do
    order = create(:order)
    create(:ticket, order:, assigned_at: Time.current, tshirt_size: nil)
    expect { described_class.perform_now }.not_to change { enqueued_jobs.size }
  end
end
