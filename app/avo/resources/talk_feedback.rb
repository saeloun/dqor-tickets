class Avo::Resources::TalkFeedback < Avo::BaseResource
  self.title = :id
  self.includes = [ :talk, :user ]

  def fields
    field :id, as: :id
    field :talk, as: :belongs_to
    field :author, as: :text, only_on: [ :index, :show ] do
      [ record.user.name.presence, record.user.email ].compact.join(" — ")
    end
    field :rating, as: :number, sortable: true
    field :comment, as: :textarea
    field :created_at, as: :date_time, only_on: :index, sortable: true
  end
end
