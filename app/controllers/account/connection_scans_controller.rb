class Account::ConnectionScansController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user
  before_action :require_legacy_network

  def show
  end
end
