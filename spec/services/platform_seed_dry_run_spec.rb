require "rails_helper"
require "rake"

RSpec.describe "platform:seed_dry_run" do
  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("platform:seed_dry_run")
    Rake::Task["platform:seed_dry_run"].reenable
  end

  it "prints a proposal without creating accounts, organizations, memberships, or events" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PLATFORM_OWNER_EMAIL").and_return("reviewed@example.com")
    before_counts = [ User.count, Organization.count, Membership.count, Event.count ]
    expect { Rake::Task["platform:seed_dry_run"].invoke }.to output(/"grants_applied": 0/).to_stdout
    expect([ User.count, Organization.count, Membership.count, Event.count ]).to eq(before_counts)
  end
end
