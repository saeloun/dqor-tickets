class Avo::Filters::OrderStatus < Avo::Filters::SelectFilter
  self.name = "Status"

  def apply(_request, query, value)
    value.present? ? query.where(status: value) : query
  end

  def options
    Order.statuses.keys.index_with(&:humanize)
  end
end
