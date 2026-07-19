class Avo::Resources::PaymentEvent < Avo::BaseResource
  self.title = :kind

  def fields
    field :id, as: :id
    field :order, as: :belongs_to, readonly: true
    field :kind, as: :text, readonly: true
    field :level, as: :text, readonly: true
    field :mode, as: :text, readonly: true
    field :amount_paise, as: :number, readonly: true
    field :razorpay_event_id, as: :text, readonly: true
    field :razorpay_payment_id, as: :text, readonly: true
    field :raw, as: :code, readonly: true
    field :created_at, as: :date_time, readonly: true
  end

  def render_show_controls
    [ BackButton.new ]
  end

  def render_index_controls(item:)
    []
  end

  def render_row_controls(item:)
    [ ShowButton.new(item:) ]
  end
end
