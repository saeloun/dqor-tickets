class Account::ConnectionScansController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def show
  end
end
