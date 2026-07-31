class HomeController < ApplicationController
  allow_unauthenticated_access

  def index
    @announcements = Announcement.published.recent.limit(3)
    @speakers = Speaker.published.ordered.limit(8)
    @sponsors = Sponsor.published.ordered.limit(8)
  end
end
