class Avo::Resources::Order < Avo::BaseResource
  self.title = :code
  self.includes = [ :coupon ]
  self.search = {
    query: -> {
      term = "%#{ActiveRecord::Base.sanitize_sql_like(q.to_s.downcase)}%"
      query.where("lower(orders.code) LIKE :term OR lower(orders.email) LIKE :term", term:)
    }
  }

  def fields
    field :id, as: :id
    field :code, as: :text, sortable: true, readonly: true
    field :status, as: :select, enum: ::Order.statuses, readonly: true
    field :buyer_name, as: :text, readonly: true
    field :email, as: :text, readonly: true
    field :buyer_phone, as: :text, readonly: true
    field :total_paise, as: :number, readonly: true
    field :coupon, as: :belongs_to, readonly: true
    field :gstin, as: :text, readonly: true
    field :gst_legal_name, as: :text, readonly: true
    field :billing_state_code, as: :text, readonly: true
    field :razorpay_order_id, as: :text, readonly: true
    field :expires_at, as: :date_time, readonly: true
    field :metadata, as: :code, readonly: true
    field :tickets, as: :has_many
    field :payment_events, as: :has_many
    field :invoices, as: :has_many
    field :refunds, as: :has_many
  end

  def filters
    filter Avo::Filters::OrderStatus
  end

  def actions
    action Avo::Actions::RefundTickets
    action Avo::Actions::ResendConfirmation
    action Avo::Actions::ExportOrdersCsv
    action Avo::Actions::ExportAttendeesCsv
  end


  def render_show_controls
    [ BackButton.new, ActionsList.new ]
  end

  def render_index_controls(item:)
    [ ActionsList.new(as_index_control: true) ]
  end

  def render_row_controls(item:)
    [ ShowButton.new(item:) ]
  end
end
