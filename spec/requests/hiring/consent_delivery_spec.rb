require "rails_helper"

RSpec.describe "Hiring consent delivery", type: :request do
  let!(:org) { Organization.create!(name: "Host", slug: "host") }
  let!(:other_org) { Organization.create!(name: "Other", slug: "other") }
  let!(:candidate) { User.create!(email: "candidate@example.test", name: "Candidate") }
  let!(:recruiter) { User.create!(email: "recipient@example.test", name: "Recipient") }
  let!(:intruder) { User.create!(email: "intruder@example.test") }
  let!(:company) { Hiring::Company.create!(organization: org, claimant: recruiter, name: "Employer", website: "https://example.test", evidence: "Offline", status: "approved") }
  let!(:job) { Hiring::Job.create!(company: company, recruiter: recruiter, title: "Engineer", description: "Remote") }
  let!(:application) { Hiring::Application.create!(job: job, applicant: candidate, snapshot: { name: "Private", summary: "Secret" }, consented_at: Time.current, quarantined_pdf: "%PDF-1.7\nSynthetic fixture") }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:hiring_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:hiring_resume_downloads_enabled).and_return(true)
  end

  def login(user)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
  end

  def scan_clean
    scanner = instance_double(Hiring::ResumeScanner)
    allow(scanner).to receive(:scan) { |bytes| Hiring::ResumeScanner::Verdict.new(status: "clean", digest: Digest::SHA256.hexdigest(bytes)) }
    allow(Rails.configuration.x).to receive(:hiring_resume_scanner).and_return(scanner)
    Hiring::ScanResumeJob.perform_now(application.id)
  end

  def request_share
    login(recruiter)
    post hiring_shares_path(job_id: job.id)
    expect(response).to have_http_status(:ok)
    @token = Nokogiri::HTML(response.body).at_css('a[href*="/hiring/recruiting/"]')["href"].split("/").last
    Hiring::ShareRequest.last
  end

  def consent
    post hiring_recruiting_path(token: @token), params: { consent: "1", recipient_id: intruder.id, snapshot: { name: "Consenting attendee", summary: "Private QR experience" } }
  end

  it "never releases unchecked PDFs and the installed adapter reports unavailable" do
    expect(Hiring::ResumeScanner.new.scan("%PDF-fixture").status).to eq("unavailable")
    Hiring::ScanResumeJob.perform_now(application.id)
    expect(application.reload.scan_status).to eq("quarantined")
    login(candidate)
    get hiring_resume_path(application)
    expect(response).to have_http_status(:not_found)
    expect(Hiring::AccessEvent.count).to eq(0)
  end

  it "releases only exact checked bytes to applicant and named recruiter with private response headers" do
    scan_clean
    [ candidate, recruiter ].each do |user|
      login(user)
      get hiring_resume_path(application)
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(application.quarantined_pdf)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    end
    expect(Hiring::AccessEvent.where(action: "resume_download").count).to eq(2)
    allow(Rails.configuration.x).to receive(:hiring_resume_downloads_enabled).and_return(false)
    get hiring_resume_path(application)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects anonymous, other-organization and sibling-event recruiters even with owner membership" do
    scan_clean
    get hiring_resume_path(application)
    expect(response).to redirect_to(account_sign_in_path)
    [ org, other_org ].each do |organization|
      Membership.create!(organization: organization, user: intruder, role: "owner")
      fixture_company = Hiring::Company.create!(organization: organization, claimant: intruder, name: "Other employer", website: "https://other.test", evidence: "Offline", status: "approved")
      event = organization.events.create!(title: "Sibling event", slug: "sibling")
      Hiring::Job.create!(company: fixture_company, recruiter: intruder, event: event, title: "Other job", description: "Other")
    end
    login(intruder)
    get hiring_resume_path(application)
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("Synthetic fixture")
  end

  it "invalidates changed bytes, failed scans and withdrawn applications" do
    scan_clean
    application.reload.update_column(:quarantined_pdf, "%PDF-different")
    login(candidate)
    get hiring_resume_path(application)
    expect(response).to have_http_status(:not_found)
    scan_clean
    scanner = instance_double(Hiring::ResumeScanner)
    allow(scanner).to receive(:scan).and_raise("Scanner failed")
    allow(Rails.configuration.x).to receive(:hiring_resume_scanner).and_return(scanner)
    expect { Hiring::ScanResumeJob.perform_now(application.id) }.to raise_error("Scanner failed")
    expect(application.reload.scan_status).to eq("quarantined")
    scan_clean
    application.withdraw!
    get hiring_resume_path(application)
    expect(response).to have_http_status(:not_found)
    expect(application.reload.quarantined_pdf).to be_nil
  end

  it "rejects mismatched scan digests and stale verdicts after concurrent replacement" do
    scanner = instance_double(Hiring::ResumeScanner)
    allow(scanner).to receive(:scan).and_return(Hiring::ResumeScanner::Verdict.new(status: "clean", digest: "wrong"))
    allow(Rails.configuration.x).to receive(:hiring_resume_scanner).and_return(scanner)
    Hiring::ScanResumeJob.perform_now(application.id)
    expect(application.reload.scan_status).to eq("quarantined")
    allow(scanner).to receive(:scan) do |bytes|
      application.update!(quarantined_pdf: "%PDF-replacement")
      Hiring::ResumeScanner::Verdict.new(status: "clean", digest: Digest::SHA256.hexdigest(bytes))
    end
    Hiring::ScanResumeJob.perform_now(application.id)
    expect(application.reload.scan_status).to eq("quarantined")
    expect(application.scan_digest).to be_nil
  end

  it "requires explicit consent and binds a single-use recruiting request to its recipient and role" do
    application.destroy!
    share = request_share
    expect(response.body).to include("not an entry ticket", "Recipient")
    login(candidate)
    get hiring_recruiting_path(token: @token)
    expect(response.body).to include("Choose whether to share", recruiter.email, "No resume is shared")
    expect(share.reload.consented_at).to be_nil
    post hiring_recruiting_path(token: @token), params: { consent: "0" }
    expect(response).to have_http_status(:unprocessable_content)
    consent
    expect(response).to have_http_status(:redirect)
    shared = share.reload.application
    expect(shared.applicant).to eq(candidate)
    expect(share.recipient).to eq(recruiter)
    expect(shared.job).to eq(job)
    expect(shared.quarantined_pdf).to be_nil
    consent
    expect(response).to have_http_status(:conflict)
    login(intruder)
    get hiring_recruiting_path(token: @token)
    expect(response).to have_http_status(:not_found)
    consent
    expect(response).to have_http_status(:conflict)
    get hiring_applicants_path(job)
    expect(response).to have_http_status(:not_found)
    delete hiring_revoke_share_path(share)
    expect(response).to have_http_status(:not_found)
    login(recruiter)
    get hiring_applicants_path(job)
    expect(response.body).to include("Private QR experience")
    login(candidate)
    delete hiring_revoke_share_path(share)
    expect(share.reload.revoked_at).to be_present
    expect(shared.reload.snapshot).to eq({})
    consent
    expect(response).to have_http_status(:conflict)
    login(recruiter)
    get hiring_applicants_path(job)
    expect(response.body).not_to include("Private QR experience")
  end

  it "denies expired requests and removes expired consent from recruiter review" do
    application.destroy!
    share = request_share
    login(candidate)
    travel 25.hours do
      get hiring_recruiting_path(token: @token)
      expect(response).to have_http_status(:not_found)
      consent
      expect(response).to have_http_status(:conflict)
    end
    consent
    expect(share.reload.consented_at).to be_present
    login(recruiter)
    travel 25.hours do
      get hiring_applicants_path(job)
      expect(response.body).not_to include("Private QR experience")
    end
  end

  it "does not permit recipient substitution or requests from unrelated recruiters" do
    login(intruder)
    post hiring_shares_path(job_id: job.id)
    expect(response).to have_http_status(:not_found)
    share = request_share
    company.update!(status: "rejected")
    login(candidate)
    consent
    expect(response).to have_http_status(:conflict)
    expect(share.reload.consented_at).to be_nil
  end
  it "rejects entry-purpose tokens and fails closed after QR withdrawal or recipient changes" do
    application.destroy!
    share = request_share
    login(candidate)
    get hiring_recruiting_path(token: "entry-ticket-token")
    expect(response).to have_http_status(:not_found)
    consent
    shared = share.reload.application
    job.update_columns(recruiter_id: intruder.id)
    login(intruder)
    get hiring_applicants_path(job)
    expect(response).to have_http_status(:not_found)
    expect(shared.consent_active?).to eq(false)
    job.update_columns(recruiter_id: recruiter.id)
    login(candidate)
    delete hiring_withdraw_path(shared)
    expect(shared.reload.consent_active?).to eq(false)
    consent
    expect(response).to have_http_status(:conflict)
    login(recruiter)
    get hiring_applicants_path(job)
    expect(response.body).not_to include("Private QR experience")
  end
end
