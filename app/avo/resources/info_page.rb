class Avo::Resources::InfoPage < Avo::BaseResource
  self.title = :title

  def fields
    field :id, as: :id
    field :title, as: :text, sortable: true
    field :slug, as: :text
    field :body, as: :textarea
    field :published, as: :boolean
    field :position, as: :number
  end
end
