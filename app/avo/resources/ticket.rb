class Avo::Resources::Ticket < Avo::BaseResource
  self.index_query = -> { query.legacy }
  self.find_record_method = -> { id.is_a?(Array) ? query.legacy.where(id: id) : query.legacy.find(id) }
  self.title = :attendee_name
  self.includes = %i[order ticket_type]

  def fields
    field :id, as: :id
    field :order, as: :belongs_to, readonly: true, attach_scope: -> { query.legacy }
    field :ticket_type, as: :belongs_to, readonly: true, attach_scope: -> { query.legacy }
    field :attendee_name, as: :text
    field :attendee_email, as: :text
    field :tshirt_size, as: :text
    field :dietary_preference, as: :text
    field :childcare_needed, as: :boolean
    field :assigned_at, as: :date_time, readonly: true
    field :price_paise, as: :number, readonly: true
    field :checked_in_at, as: :code, readonly: true
    field :canceled_at, as: :date_time, readonly: true
    field :pdf, as: :file, readonly: true
  end

  def actions
    action Avo::Actions::OpenCheckin
    action Avo::Actions::RequestAttendeeDetails
  end
end
