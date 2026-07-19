class CheckoutPreviewsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { head :too_many_requests }

  def create
    preview = params.expect(checkout_preview: [ :coupon_code, items: [ [ :ticket_type_id, :quantity ] ] ])
    subtotals = subtotals_for(preview.fetch(:items, []))
    coupon = Coupon.find_by_code(preview[:coupon_code])
    discount = coupon ? coupon.discount_for(subtotals) : 0

    render json: quote(subtotals, coupon_code: preview[:coupon_code], coupon:, discount:)
  rescue Coupon::Invalid => error
    render json: quote(subtotals, coupon_code: preview[:coupon_code], message: error.message)
  end

  private
    def subtotals_for(items)
      quantities = items.each_with_object(Hash.new(0)) do |item, result|
        ticket_type_id = Integer(item[:ticket_type_id], exception: false)
        quantity = Integer(item[:quantity], exception: false)
        next unless ticket_type_id&.positive? && ticket_type_id.bit_length <= 63 && quantity&.positive?

        result[ticket_type_id] += quantity
      end

      TicketType.where(id: quantities.keys, hidden: false).to_h do |ticket_type|
        [ ticket_type.id, ticket_type.price_paise * quantities.fetch(ticket_type.id) ]
      end
    end

    def quote(subtotals, coupon_code:, coupon: nil, discount: 0, message: nil)
      subtotal = subtotals.values.sum
      {
        subtotal_paise: subtotal,
        discount_paise: discount,
        total_paise: subtotal - discount,
        coupon: {
          code: coupon&.code || coupon_code.to_s.strip.upcase,
          applied: coupon.present?,
          message:
        }
      }
    end
end
