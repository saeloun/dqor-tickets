class Hiring::SharesController < Hiring::BoardController
  def create
    job = Hiring::Job.visible.joins(:company).where(recruiter: current_user, hiring_companies: { claimant_id: current_user.id }).find(params[:job_id])
    token = SecureRandom.urlsafe_base64(32)
    @share = Hiring::ShareRequest.create!(job: job, recipient: current_user, token_digest: Digest::SHA256.hexdigest(token), expires_at: 24.hours.from_now)
    @url = hiring_recruiting_url(token: token)
    @qr = RQRCode::QRCode.new(@url).as_svg(module_size: 4, standalone: true)
  end

  def show
    @share = find_request
    head :not_found unless @share.available? && Hiring::Job.visible.exists?(@share.job_id)
  end

  def confirm
    @share = find_request
    return head :unprocessable_content unless params[:consent] == "1"
    @share.with_lock do
      return head :conflict unless @share.available? && Hiring::Job.visible.exists?(@share.job_id)
      application = Hiring::Application.new(job: @share.job, applicant: current_user, share_request: @share, consented_at: Time.current, snapshot: params.expect(snapshot: [ :name, :summary, :linkedin ]).to_h.merge("email" => current_user.email))
      if application.save
        @share.update!(applicant: current_user, consented_at: application.consented_at)
        Hiring::AccessEvent.create!(application: application, user: current_user, action: "qr_consent")
      else
        return render plain: application.errors.full_messages.join(". "), status: :unprocessable_content
      end
    end
    redirect_to hiring_root_path, notice: "Shared with the named recruiter until the displayed expiry. You can revoke at any time."
  rescue ActiveRecord::RecordNotUnique
    head :conflict
  end

  def revoke
    share = Hiring::ShareRequest.where(applicant: current_user).find(params[:id])
    share.with_lock do
      share.update!(revoked_at: Time.current)
      share.application.withdraw!
      Hiring::AccessEvent.create!(application: share.application, user: current_user, action: "qr_revocation")
    end
    redirect_to hiring_root_path, notice: "Sharing revoked and snapshot erased."
  end

  private
    def find_request
      Hiring::ShareRequest.find_by!(token_digest: Digest::SHA256.hexdigest(params[:token].to_s))
    end
end
