class Finance::BaseController < ApplicationController
  layout "private_document"
  before_action :require_finance_admin
  before_action :private_response

  private
    def require_finance_admin
      head :forbidden unless Current.admin_user&.admin?
    end

    def private_response
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["Referrer-Policy"] = "no-referrer"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end
end
