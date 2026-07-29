require "rails_helper"

RSpec.describe WeeklyAssignmentRemindersJob, type: :job do
  it "reminds buyers who still have an unassigned ticket" do
    order = create(:order, :paid)
    create(:ticket, order:, attendee_name: nil, attendee_email: nil, assigned_at: nil)

    expect { described_class.perform_now }
      .to have_enqueued_mail(OrderMailer, :order_link).with(order)
  end

  it "reminds assigned attendees who are missing details" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:, assigned_at: Time.current, tshirt_size: nil)

    expect { described_class.perform_now }
      .to have_enqueued_mail(OrderMailer, :complete_details).with(ticket)
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
      .to have_enqueued_mail(OrderMailer, :order_link).with(order).once
  end
end
