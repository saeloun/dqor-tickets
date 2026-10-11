class Avo::Resources::WallLoveNote < Avo::BaseResource
  self.title = :public_name

  def fields
    field :id, as: :id
    field :public_name, as: :text, readonly: true
    field :note, as: :textarea, readonly: true
    field :source_url, as: :text, readonly: true
    field :publication_consent, as: :boolean, readonly: true
    field :status, as: :text, readonly: true
    field :created_at, as: :date_time, readonly: true, sortable: true
    field :reviewed_at, as: :date_time, readonly: true
  end

  def actions
    action Avo::Actions::ReviewWallLoveNote
  end
end
