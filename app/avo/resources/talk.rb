class Avo::Resources::Talk < Avo::BaseResource
  self.title = :title

  def fields
    field :id, as: :id
    field :title, as: :text, sortable: true
    field :speaker_name, as: :text
    field :speaker_bio, as: :textarea
    field :abstract, as: :textarea
    field :starts_at, as: :date_time
    field :ends_at, as: :date_time
    field :room, as: :text
    field :track, as: :text
    field :published, as: :boolean
    field :position, as: :number
  end
end
