class Hiring::ResumesController < Hiring::BoardController
  def show
    application = Hiring::Application.find(params[:id])
    job = application.job
    owner = application.applicant_id == current_user.id
    recruiter = job.recruiter_id == current_user.id && job.company.claimant_id == current_user.id && job.company.status == "approved"
    return head :not_found unless owner || recruiter
    application.with_lock do
      return head :not_found unless application.resume_releasable?
      Hiring::AccessEvent.create!(application: application, user: current_user, action: "resume_download")
      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["Content-Security-Policy"] = "default-src 'none'; sandbox"
      send_data application.quarantined_pdf, type: "application/pdf", disposition: "attachment", filename: "resume.pdf"
    end
  end
end
