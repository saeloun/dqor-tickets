class Avo::Resources::Invoice < Avo::BaseResource
  self.index_query = -> { query.legacy }
  self.find_record_method = -> { id.is_a?(Array) ? query.legacy.where(id: id) : query.legacy.find(id) }
  self.title = :number

  def fields
    field :id, as: :id
    field :number, as: :text, readonly: true
    field :kind, as: :text, readonly: true
    field :issued_on, as: :date, readonly: true
    field :order, as: :belongs_to, readonly: true, attach_scope: -> { query.legacy }
    field :refers_to, as: :belongs_to, readonly: true, attach_scope: -> { query.legacy }
    field :buyer_snapshot, as: :code, readonly: true
    field :line_items, as: :code, readonly: true
    field :pdf, as: :file, readonly: true
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
