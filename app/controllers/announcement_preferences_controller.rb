class AnnouncementPreferencesController < ApplicationController
  rescue_from ActiveSupport::MessageVerifier::InvalidSignature, with: -> { head :not_found }
  allow_unauthenticated_access
  before_action :require_user, only: :update

  def update
    preference = AnnouncementPreference.find_or_create_by!(email: current_user.email)
    preference.with_lock do
      if params[:subscribe] == "1"
        preference.update!(consented_at: Time.current, suppressed_at: nil, consent_source: "authenticated_account_settings")
      else
        preference.update!(suppressed_at: Time.current)
      end
    end
    redirect_to account_settings_path, notice: "Announcement email preference saved."
  end

  def unsubscribe
    @preference = AnnouncementPreference.find_signed!(params[:token], purpose: :announcement_unsubscribe)
  end

  def suppress
    preference = AnnouncementPreference.find_signed!(params[:token], purpose: :announcement_unsubscribe)
    preference.update!(suppressed_at: Time.current)
    render plain: "You are unsubscribed from announcement emails. Transactional ticket and account emails are unaffected."
  end
end
