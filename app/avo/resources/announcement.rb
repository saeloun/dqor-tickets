class Avo::Resources::Announcement < Avo::BaseResource
  self.title = :title

  def fields
    field :id, as: :id
    field :title, as: :text, sortable: true
    field :body, as: :textarea
    field :published, as: :boolean
    field :published_at, as: :date_time
    field :emailed_at, as: :date_time, readonly: true,
      help: "Set automatically when this announcement is emailed to ticket holders."
  end

  def actions
    action Avo::Actions::BroadcastAnnouncement
  end
end
