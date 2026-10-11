class WallOfLoveController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user, except: :show
  before_action :require_attendee, only: %i[create update]
  rate_limit to: 5, within: 5.minutes, only: %i[create update], by: -> { current_user&.id || request.remote_ip }, with: -> { head :too_many_requests }

  def show
    load_wall
  end

  def create
    @submission = WallLoveNote.find_by(user: current_user)
    if @submission
      redirect_to wall_of_love_path(anchor: "your-note"), notice: "You already have a note. You can edit it below."
    else
      @submission = WallLoveNote.new(submission_params.merge(user: current_user))
      save_submission
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to wall_of_love_path(anchor: "your-note"), notice: "Your note has already been received."
  end

  def update
    @submission = WallLoveNote.find_by!(user: current_user)
    revision = params.expect(wall_love_note: [ :lock_version ])[:lock_version]
    raise ActionController::ParameterMissing, :lock_version unless revision.to_s.match?(/\A\d+\z/)

    @submission.assign_attributes(submission_params.merge(lock_version: revision))
    @submission.status = :pending
    save_submission
  rescue ActiveRecord::StaleObjectError
    redirect_to wall_of_love_path(anchor: "your-note"), alert: "Your note changed in another tab. Review the latest version and try again."
  end

  def destroy
    submission = WallLoveNote.find_by!(user: current_user)
    submission.with_lock { submission.update!(status: :withdrawn, publication_consent: false, reviewed_by: nil, reviewed_at: nil) unless submission.withdrawn? }
    redirect_to wall_of_love_path(anchor: "your-note"), notice: "Your note is withdrawn and is no longer public."
  end

  private
    def require_attendee
      head :forbidden unless current_user.attending?
    end

    def submission_params
      params.expect(wall_love_note: [ :public_name, :note, :source_url, :publication_consent ])
    end

    def load_wall
      @notes = WallLoveNote.published.order(id: :desc).limit(100)
      @submission ||= WallLoveNote.find_by(user: current_user) if current_user
      @submission ||= WallLoveNote.new
    end

    def save_submission
      if @submission.save
        redirect_to wall_of_love_path(anchor: "your-note"), notice: "Thank you! Your note is pending review before publication."
      else
        load_wall
        render :show, status: :unprocessable_content
      end
    end
end
