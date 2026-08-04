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
    field :status, as: :select, enum: ::Speaker.statuses,
      help: "Pipeline status. Only 'announced' speakers can appear publicly (and only when Published is on)."
    field :published, as: :boolean, help: "Show on the public /speakers page (requires status = announced)."
    field :position, as: :number
  end
end
