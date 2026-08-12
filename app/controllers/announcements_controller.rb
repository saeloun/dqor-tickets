class AnnouncementsController < ApplicationController
  allow_unauthenticated_access

  def index
    @announcements = Announcement.published.recent
    current_user&.mark_announcements_seen!
  end
end
