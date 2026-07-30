class AnnouncementsController < ApplicationController
  allow_unauthenticated_access

  def index
    @announcements = Announcement.published.recent
  end
end
