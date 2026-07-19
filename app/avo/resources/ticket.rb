class Avo::Resources::Ticket < Avo::BaseResource
  self.title = :attendee_name
  self.includes = %i[order ticket_type]

  def fields
    field :id, as: :id
    field :order, as: :belongs_to, readonly: true
    field :ticket_type, as: :belongs_to, readonly: true
    field :attendee_name, as: :text
    field :attendee_email, as: :text
    field :tshirt_size, as: :text
    field :dietary_preference, as: :text
    field :price_paise, as: :number, readonly: true
    field :secret, as: :text, readonly: true
    field :checked_in_at, as: :code, readonly: true
    field :canceled_at, as: :date_time, readonly: true
    field :pdf, as: :file, readonly: true
  end
end
