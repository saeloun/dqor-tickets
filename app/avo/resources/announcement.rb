class Avo::Resources::Announcement < Avo::BaseResource
  self.title = :title

  def fields
    field :id, as: :id
    field :title, as: :text, sortable: true
    field :body, as: :textarea
    field :published, as: :boolean
    field :published_at, as: :date_time
    field :emailed_at, as: :date_time, readonly: true,
      help: "Legacy sent marker. Use Preview and approve email for current delivery status."
  end

  def actions
    action Avo::Actions::BroadcastAnnouncement
  end
end
