class Hiring::BoardController < ApplicationController
  layout "hiring"
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  allow_unauthenticated_access
  prepend_before_action :enabled
  before_action :require_user
  before_action :private_response

  def index
    @jobs = Hiring::Job.visible.includes(:company, :event).order(created_at: :desc)
    @jobs = @jobs.where(event_id: params[:event_id]) if params[:event_id].present?
    @companies = Hiring::Company.where(claimant: current_user)
    @applications = Hiring::Application.where(applicant: current_user).includes(job: :company)
    @claims = Hiring::Company.where(organization_id: Membership.where(user: current_user, role: %w[owner admin]).select(:organization_id), status: "pending").where.not(claimant: current_user)
    @organizations = Organization.order(:name)
    @affiliations = Hiring::Affiliation.where(user: current_user).includes(:company)
  end

  def claim
    company = Hiring::Company.new(params.expect(company: [ :name, :website, :evidence, :organization_id ]))
    company.claimant = current_user
    save_and_return(company)
  end

  def review_claim
    company = Hiring::Company.find(params[:id])
    Membership.where(role: %w[owner admin]).find_by!(user: current_user, organization: company.organization)
    return head :forbidden if company.claimant == current_user
    company.with_lock do
      return head :conflict unless company.status == "pending"
      company.update!(status: params[:decision] == "approve" ? "approved" : "rejected", reviewer: current_user)
    end
    redirect_to hiring_root_path
  end

  def create_job
    company = Hiring::Company.where(status: "approved", claimant: current_user).find(params[:company_id])
    job = Hiring::Job.new(params.expect(job: [ :title, :description, :event_id ]))
    job.company = company
    job.recruiter = current_user
    save_and_return(job)
  end

  def show
    @job = Hiring::Job.visible.find(params[:id])
  end

  def apply
    job = Hiring::Job.visible.find(params[:id])
    return head :unprocessable_content unless params[:consent] == "1"
    application = Hiring::Application.new(job: job, applicant: current_user, snapshot: params.expect(snapshot: [ :name, :summary, :linkedin ]).to_h.merge("email" => current_user.email), consented_at: Time.current)
    if (upload = params[:resume]).present?
      return head :unprocessable_content unless upload.respond_to?(:read) && upload.content_type == "application/pdf"
      application.quarantined_pdf = upload.read(Hiring::Application::MAX_PDF_BYTES + 1)
    end
    save_and_return(application)
  rescue ActiveRecord::RecordNotUnique
    head :conflict
  end

  def withdraw
    Hiring::Application.where(applicant: current_user).find(params[:id]).withdraw!
    redirect_to hiring_root_path
  end

  def applicants
    @job = Hiring::Job.joins(:company).where(recruiter: current_user, hiring_companies: { status: "approved", claimant_id: current_user.id }).find(params[:id])
    @applications = Hiring::Application.where(job: @job, withdrawn_at: nil).includes(share_request: { job: :company }).select(&:consent_active?)
  end

  def remove_affiliation
    Hiring::Affiliation.where(user: current_user).find(params[:id]).destroy!
    redirect_to hiring_root_path
  end

  def affiliate
    company = Hiring::Company.where(status: "approved").find(params[:company_id])
    Hiring::Affiliation.find_or_create_by!(company: company, user: current_user)
    redirect_to hiring_root_path, notice: "Self-reported affiliation saved. It grants no recruiting or administrative access."
  end

  private
    def enabled
      head :not_found unless Rails.configuration.x.hiring_enabled && Rails.configuration.x.organizer_platform_enabled
    end

    def private_response
      response.headers["Cache-Control"] = "no-store"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      response.headers["Referrer-Policy"] = "no-referrer"
    end

    def save_and_return(record)
      if record.save
        redirect_to hiring_root_path, notice: "Saved."
      else
        render plain: record.errors.full_messages.join(". "), status: :unprocessable_content
      end
    end
end
