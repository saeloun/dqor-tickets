class Avo::Resources::Speaker < Avo::BaseResource
  self.title = :name

  def fields
    field :id, as: :id
    field :name, as: :text, sortable: true
    field :title, as: :text
    field :bio, as: :textarea
    field :twitter, as: :text
    field :github, as: :text
    field :photo, as: :file, is_image: true
    field :published, as: :boolean
    field :position, as: :number
  end
end
