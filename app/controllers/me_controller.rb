class MeController < ApplicationController
  skip_before_action :require_authentication
  before_action :require_user_authentication

  def show
    @going = current_user.registrations.going.includes(:event)
    @interested = current_user.registrations.interested.includes(:event)
    @past = current_user.registrations
      .joins(:event)
      .where("events.ends_at < ?", Time.current)
      .includes(:event)
  end
end
