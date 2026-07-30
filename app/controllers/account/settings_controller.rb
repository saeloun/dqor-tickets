class Account::SettingsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def show
  end

  def update
    if current_user.update(settings_params)
      redirect_to account_settings_path, notice: "Your settings are saved."
    else
      render :show, status: :unprocessable_content
    end
  end

  private
    def settings_params
      permitted = params.expect(user: [ :name, :bio, :discoverable, :avatar, :password ])
      permitted.delete(:password) if permitted[:password].blank?
      permitted
    end
end
