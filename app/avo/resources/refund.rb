class Avo::Resources::Refund < Avo::BaseResource
  self.title = :razorpay_refund_id

  def fields
    field :id, as: :id
    field :order, as: :belongs_to
    field :amount_paise, as: :number
    field :status, as: :text
    field :ticket_ids, as: :code
    field :razorpay_refund_id, as: :text
    field :credit_note_number, as: :text
  end
end
