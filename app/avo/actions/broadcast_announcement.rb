class Avo::Actions::BroadcastAnnouncement < Avo::BaseAction
  self.name = "Preview and approve email"
  self.confirmation = false

  def handle(query:, **)
    return error "Administrator access required" unless Current.admin_user&.admin?
    announcements = query.first(2)
    return error "Select one announcement to review its content and audience." unless announcements.size == 1
    redirect_to Rails.application.routes.url_helpers.announcement_campaign_path(announcements.first)
  end
end
