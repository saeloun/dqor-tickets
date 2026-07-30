class LoginsController < ApplicationController
  allow_unauthenticated_access only: %i[show]

  def show
    session[:return_to_after_authenticating] = safe_return_to if params[:return_to].present?
  end

  private
    def safe_return_to
      params[:return_to].to_s.start_with?("/") ? params[:return_to] : nil
    end
end
