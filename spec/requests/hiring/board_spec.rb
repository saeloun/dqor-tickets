require "rails_helper"

RSpec.describe "Private hiring", type: :request do
  let!(:org) { Organization.create!(name: "One", slug: "one") }
  let!(:other_org) { Organization.create!(name: "Two", slug: "two") }
  let!(:candidate) { User.create!(email: "candidate@example.test", name: "Candidate") }
  let!(:recruiter) { User.create!(email: "recruiter@example.test") }
  let!(:other_recruiter) { User.create!(email: "other@example.test") }
  let!(:owner) { User.create!(email: "owner@example.test") }
  let!(:company) { Hiring::Company.create!(organization: org, claimant: recruiter, name: "Independent", website: "https://example.test", evidence: "Manual evidence", status: "approved") }
  let!(:event) { org.events.create!(title: "Published", slug: "published", status: "published", starts_at: 1.day.from_now, ends_at: 2.days.from_now) }
  let!(:job) { Hiring::Job.create!(company: company, recruiter: recruiter, event: event, title: "Engineer", description: "Build useful things") }

  before do
    allow(Rails.configuration.x).to receive(:organizer_platform_enabled).and_return(true)
    allow(Rails.configuration.x).to receive(:hiring_enabled).and_return(true)
  end

  def login(user)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
  end

  def apply_to_job(extra = {})
    post hiring_apply_path(job), params: { consent: "1", snapshot: { name: "Private candidate", summary: "Secret experience", linkedin: "https://www.linkedin.com/in/example" } }.merge(extra)
  end

  it "defaults to a gated, authenticated surface" do
    get hiring_root_path
    expect(response).to redirect_to(account_sign_in_path)
    login(candidate)
    allow(Rails.configuration.x).to receive(:hiring_enabled).and_return(false)
    get hiring_root_path
    expect(response).to have_http_status(:not_found)
    apply_to_job
    expect(response).to have_http_status(:not_found)
  end

  it "shows global and published event jobs without leaking draft events" do
    global = Hiring::Job.create!(company: company, recruiter: recruiter, title: "Global role", description: "Remote")
    draft = org.events.create!(title: "Secret event", slug: "secret")
    Hiring::Job.create!(company: company, recruiter: recruiter, event: draft, title: "Secret role", description: "Hidden")
    login(candidate)
    get hiring_root_path
    expect(response.body).to include("Global role", "Engineer")
    expect(response.body).not_to include("Secret role", "Secret event")
    get hiring_root_path, params: { event_id: event.id }
    expect(response.body).to include("Engineer")
    expect(response.body).not_to include(global.title)
    event.update!(status: "draft")
    get hiring_job_path(job)
    expect(response).to have_http_status(:not_found)
  end

  it "requires consent, snapshots only allowlisted data, and supports applicant-owned erasure" do
    login(candidate)
    apply_to_job(consent: "0")
    expect(response).to have_http_status(:unprocessable_content)
    expect(Hiring::Application.count).to eq(0)
    apply_to_job(applicant_id: recruiter.id)
    expect(response).to have_http_status(:redirect)
    application = Hiring::Application.last
    expect(application.applicant).to eq(candidate)
    candidate.update!(name: "Changed")
    expect(application.snapshot["name"]).to eq("Private candidate")
    login(recruiter)
    get hiring_applicants_path(job)
    expect(response.body).to include("Secret experience")
    expect(response.headers["Cache-Control"]).to include("no-store")
    delete hiring_withdraw_path(application)
    expect(response).to have_http_status(:not_found)
    login(candidate)
    delete hiring_withdraw_path(application)
    expect(application.reload.snapshot).to eq({})
    expect(application.withdrawn_at).to be_present
    login(recruiter)
    get hiring_applicants_path(job)
    expect(response.body).not_to include("Secret experience")
  end

  it "denies other organizations and other event recruiters in the same organization, even owners" do
    login(candidate)
    apply_to_job
    [ org, other_org ].each do |scope|
      Membership.create!(organization: scope, user: other_recruiter, role: "owner")
      employer = Hiring::Company.create!(organization: scope, claimant: other_recruiter, name: "Other", website: "https://other.test", evidence: "Evidence", status: "approved")
      sibling = scope.events.create!(title: "Sibling", slug: "sibling")
      Hiring::Job.create!(company: employer, recruiter: other_recruiter, event: sibling, title: "Other role", description: "Other")
    end
    login(other_recruiter)
    get hiring_applicants_path(job)
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("Secret experience")
    login(candidate)
    get hiring_applicants_path(job)
    expect(response).to have_http_status(:not_found)
    login(recruiter)
    company.update!(status: "rejected")
    get hiring_applicants_path(job)
    expect(response).to have_http_status(:not_found)
  end

  it "keeps employer affiliation separate from all permissions" do
    login(candidate)
    expect { post hiring_affiliation_path(company_id: company.id) }.to change(Hiring::Affiliation, :count).by(1)
    expect(Membership.where(user: candidate)).to be_empty
    affiliation = Hiring::Affiliation.last
    login(other_recruiter)
    delete hiring_remove_affiliation_path(affiliation)
    expect(response).to have_http_status(:not_found)
    login(candidate)
    delete hiring_remove_affiliation_path(affiliation)
    expect(Hiring::Affiliation.exists?(affiliation.id)).to eq(false)
    get hiring_applicants_path(job)
    expect(response).to have_http_status(:not_found)
    post hiring_jobs_path(company_id: company.id), params: { job: { title: "Hijack", description: "No" } }
    expect(response).to have_http_status(:not_found)
  end

  it "requires scoped independent owner/admin claim approval and never grants membership" do
    login(candidate)
    post hiring_claims_path, params: { company: { organization_id: org.id, name: "New employer", website: "https://new.test", evidence: "Verify me", status: "approved", claimant_id: owner.id } }
    claim = Hiring::Company.last
    expect(claim).to have_attributes(status: "pending", claimant_id: candidate.id)
    Membership.create!(organization: org, user: candidate, role: "owner")
    post hiring_review_claim_path(claim), params: { decision: "approve" }
    expect(response).to have_http_status(:forbidden)
    login(owner)
    membership = Membership.create!(organization: other_org, user: owner, role: "owner")
    post hiring_review_claim_path(claim), params: { decision: "approve" }
    expect(response).to have_http_status(:not_found)
    membership.update!(organization: org, role: "editor")
    post hiring_review_claim_path(claim), params: { decision: "approve" }
    expect(response).to have_http_status(:not_found)
    membership.update!(role: "admin")
    expect { post hiring_review_claim_path(claim), params: { decision: "approve" } }.not_to change(Membership, :count)
    expect(claim.reload.status).to eq("approved")
  end

  it "rejects cross-tenant job events" do
    foreign_event = other_org.events.create!(title: "Other", slug: "other")
    login(recruiter)
    post hiring_jobs_path(company_id: company.id), params: { job: { title: "Wrong tenant", description: "No", event_id: foreign_event.id } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "quarantines bounded PDFs, rejects spoofed content and erases bytes on withdrawal" do
    login(candidate)
    file = Tempfile.new([ "resume", ".pdf" ])
    file.binmode
    file.write("%PDF-1.7\nunchecked")
    file.flush
    apply_to_job(resume: Rack::Test::UploadedFile.new(file.path, "application/pdf"))
    application = Hiring::Application.last
    expect(application.quarantined_pdf).to start_with("%PDF-")
    login(recruiter)
    get hiring_applicants_path(job)
    expect(response.body).to include("unchecked and unavailable")
    expect(response.body).not_to include("%PDF-1.7")
    login(candidate)
    delete hiring_withdraw_path(application)
    expect(application.reload.quarantined_pdf).to be_nil
    application.destroy!
    file.rewind
    file.truncate(0)
    file.write("not a PDF")
    file.flush
    apply_to_job(resume: Rack::Test::UploadedFile.new(file.path, "application/pdf"))
    expect(response).to have_http_status(:unprocessable_content)
    file.rewind
    file.write("%PDF-" + "x" * Hiring::Application::MAX_PDF_BYTES)
    file.flush
    apply_to_job(resume: Rack::Test::UploadedFile.new(file.path, "application/pdf"))
    expect(response).to have_http_status(:unprocessable_content)
    expect(Hiring::Application.count).to eq(0)
  ensure
    file&.close!
  end
end
