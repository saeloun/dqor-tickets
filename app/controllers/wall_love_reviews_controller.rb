class WallLoveReviewsController < ApplicationController
  helper WallOfLoveHelper
  before_action :require_admin
  before_action :load_note

  def show
  end

  def update
    @note.moderate!(decision: params[:decision], revision: params[:lock_version], admin: Current.admin_user)
    redirect_to wall_love_review_path(@note), notice: "Review decision saved."
  rescue WallLoveNote::ReviewChanged
    redirect_to wall_love_review_path(@note), alert: "The decision could not be saved. Review the current content and status before trying again."
  end

  private
    def require_admin
      head :forbidden unless Current.admin_user&.admin?
    end

    def load_note
      @note = WallLoveNote.find(params[:id])
    end
end
