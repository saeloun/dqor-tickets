class Avo::Resources::Announcement < Avo::BaseResource
  self.title = :title

  def fields
    field :id, as: :id
    field :title, as: :text, sortable: true
    field :body, as: :textarea
    field :published, as: :boolean
    field :published_at, as: :date_time
  end
end
