require "rails_helper"
require "yaml"

RSpec.describe "Concluded conference assignment reminders", type: :job do
  let(:cutoff) { Time.utc(2026, 10, 11, 18, 30) }

  before { ActionMailer::Base.deliveries.clear }

  def pending_assignments
    order = create(:order, :paid)
    create(:ticket, order:, attendee_name: nil, attendee_email: nil, assigned_at: nil)
    ticket = create(:ticket, order:, assigned_at: Time.current, tshirt_size: nil)
    [ order, ticket ]
  end

  it "retains reminders through the final event day in Asia/Kolkata" do
    travel_to(cutoff - 1.second) do
      pending_assignments
      perform_enqueued_jobs { WeeklyAssignmentRemindersJob.perform_now }
      expect(ActionMailer::Base.deliveries.size).to eq(2)
    end
  end

  it "does not enqueue reminders at the start of the next day in Asia/Kolkata" do
    travel_to(cutoff) do
      pending_assignments
      expect { WeeklyAssignmentRemindersJob.perform_now }.not_to change { enqueued_jobs.size }
    end
  end

  it "uses the conference timezone even while the application is still on the previous date" do
    Time.use_zone("America/Los_Angeles") do
      travel_to(cutoff) do
        expect(Date.current).to eq(Date.new(2026, 10, 11))
        pending_assignments
        expect { WeeklyAssignmentRemindersJob.perform_now }.not_to change { enqueued_jobs.size }
      end
    end
  end

  it "makes an already queued weekly job harmless after the event ends" do
    travel_to(cutoff - 1.minute) do
      pending_assignments
      WeeklyAssignmentRemindersJob.perform_later
    end
    travel_to(cutoff) { perform_enqueued_jobs }
    expect(enqueued_jobs).to be_empty
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  [ :order_link, :complete_details ].each do |action|
    it "does not deliver a marked #{action} reminder queued before the cutoff but executed afterward" do
      order, ticket = pending_assignments
      travel_to(cutoff - 1.minute) do
        OrderMailer.with(weekly_assignment_reminder: true).public_send(action, action == :order_link ? order : ticket).deliver_later
      end
      travel_to(cutoff) { perform_enqueued_jobs }
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it "preserves manual order links, manual details requests, and confirmations after the cutoff" do
    travel_to(cutoff) do
      order, ticket = pending_assignments
      perform_enqueued_jobs do
        order.deliver_order_link!
        ticket.request_details!
        OrderMailer.confirmation(order, documents_pending: true).deliver_later
      end
      expect(ActionMailer::Base.deliveries.map(&:subject)).to contain_exactly(
        "Your Deccan Queen on Rails order link", "One quick thing for your Deccan Queen on Rails ticket", "Your Deccan Queen on Rails tickets"
      )
    end
  end

  it "removes the obsolete recurring schedule while preserving other recurring tasks" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")
    expect(recurring).not_to have_key("weekly_assignment_reminders")
    expect(recurring.keys).to include("announcement_dispatch", "expire_orders", "reconcile_payments", "clear_solid_queue_finished_jobs")
  end
end
