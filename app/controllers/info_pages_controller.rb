class InfoPagesController < ApplicationController
  allow_unauthenticated_access

  def index
    @pages = InfoPage.published.ordered
  end

  def show
    @page = InfoPage.published.find_by!(slug: params[:slug])
  end
end
