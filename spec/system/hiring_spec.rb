require "rails_helper"

RSpec.describe "Mobile hiring", type: :system do
  it "submits and withdraws a private application at mobile width" do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:hiring_enabled).and_return(true)
    organization = Organization.create!(name: "Host", slug: "host")
    recruiter = User.create!(email: "mobile-recruiter@example.test")
    company = Hiring::Company.create!(organization: organization, claimant: recruiter, name: "Independent employer", website: "https://example.test", evidence: "Checked offline", status: "approved")
    Hiring::Job.create!(company: company, recruiter: recruiter, title: "Mobile engineer", description: "Remote position")
    candidate = User.create!(email: "mobile-candidate@example.test", name: "Mobile Candidate")
    token = Rails.application.message_verifier(:account_magic_link).generate(candidate.id, purpose: :account_magic_link, expires_in: 30.minutes)
    page.driver.resize(390, 844)
    visit account_magic_path(token: token)
    expect(page).to have_content("Mobile Candidate")
    visit hiring_root_path
    click_link "Mobile engineer"
    fill_in "Experience and interest", with: "Private engineering experience"
    check "I consent to sharing this snapshot and my account email with this role's recruiter."
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to eq(true)
    click_button "Submit application"
    expect(page).to have_content("Submitted")
    click_button "Withdraw and delete profile snapshot"
    expect(page).to have_content("Withdrawn")
    expect(Hiring::Application.last.snapshot).to eq({})
  end
end
