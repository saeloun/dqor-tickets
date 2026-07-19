require "rails_helper"

RSpec.describe ExpireOrdersJob, type: :job do
  it "expires overdue pending orders" do
    overdue = create(:order, expires_at: 1.minute.ago)
    current = create(:order, expires_at: 1.minute.from_now)

    described_class.perform_now

    expect(overdue.reload).to be_expired
    expect(current.reload).to be_pending
  end
end
