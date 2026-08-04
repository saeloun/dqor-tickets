class Avo::Actions::BroadcastAnnouncement < Avo::BaseAction
  self.name = "Email to ticket holders"
  self.confirmation = true
  self.message = "Email the selected announcement to every attendee with a paid ticket. " \
    "This sends real email and can only be done once per announcement."

  def handle(query:, **)
    queued = query.reject(&:emailed_at?)

    queued.each { |announcement| BroadcastAnnouncementJob.perform_later(announcement) }

    if queued.any?
      succeed "Queued #{queued.size} announcement(s) to email to ticket holders."
    else
      error "Already emailed. Nothing was re-sent."
    end
  end
end
