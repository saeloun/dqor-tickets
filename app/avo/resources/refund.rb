class Avo::Resources::Refund < Avo::BaseResource
  self.index_query = -> { query.legacy }
  self.find_record_method = -> { id.is_a?(Array) ? query.legacy.where(id: id) : query.legacy.find(id) }
  self.title = :razorpay_refund_id

  def fields
    field :id, as: :id
    field :order, as: :belongs_to, attach_scope: -> { query.legacy }
    field :amount_paise, as: :number
    field :status, as: :text
    field :ticket_ids, as: :code
    field :razorpay_refund_id, as: :text
    field :credit_note_number, as: :text
  end
end
