class Avo::Resources::TalkQuestion < Avo::BaseResource
  self.title = :body
  self.includes = [ :talk, :user ]

  def fields
    field :id, as: :id
    field :talk, as: :belongs_to
    field :user, as: :belongs_to
    field :body, as: :textarea
    field :answered_at, as: :date_time, help: "Set to mark this question as answered on the talk page."
    field :created_at, as: :date_time, only_on: :index, sortable: true
  end
end
