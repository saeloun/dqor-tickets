class Avo::Resources::Faq < Avo::BaseResource
  self.title = :question

  def fields
    field :id, as: :id
    field :question, as: :text
    field :answer, as: :textarea
    field :published, as: :boolean
    field :position, as: :number
  end
end
