class Avo::Resources::Sponsor < Avo::BaseResource
  self.title = :name

  def fields
    field :id, as: :id
    field :name, as: :text, sortable: true
    field :url, as: :text
    field :tier, as: :text
    field :blurb, as: :textarea
    field :logo, as: :file, is_image: true
    field :published, as: :boolean
    field :position, as: :number
  end
end
