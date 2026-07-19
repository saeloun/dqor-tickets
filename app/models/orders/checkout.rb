module Orders
  class Checkout
    class SoldOut < StandardError; end
    class InvalidSelection < StandardError; end
    class ConferencePassRequired < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(order_attributes:, items:, coupon_code: nil, conference_order_code: nil, conference_order_email: nil)
      @order_attributes = order_attributes
      @items = items
      @coupon_code = coupon_code
      @conference_order_code = conference_order_code
      @conference_order_email = conference_order_email
    end

    def call
      Order.transaction do
        selections = normalize_items
        ticket_types = TicketType.where(id: selections.pluck(:ticket_type_id)).order(:id).index_by(&:id)
        raise InvalidSelection, "ticket type not found" unless ticket_types.size == selections.size

        validate_selections!(selections, ticket_types)
        validate_conference_pass!(selections, ticket_types)

        subtotals = selections.to_h do |selection|
          type = ticket_types.fetch(selection[:ticket_type_id])
          [ type.id, type.price_paise * selection[:quantity] ]
        end
        coupon = find_coupon
        discount = coupon ? coupon.discount_for(subtotals) : 0
        metadata = coupon ? { "coupon_code" => coupon.code, "discount_paise" => discount, "coupon_ticket_type_id" => coupon.ticket_type_id } : {}
        order = Order.create!(**@order_attributes, coupon:, total_paise: subtotals.values.sum - discount, expires_at: 30.minutes.from_now, metadata:)

        selections.each do |selection|
          type = ticket_types.fetch(selection[:ticket_type_id])
          selection[:quantity].times do |index|
            attributes = selection[:attendees][index]&.symbolize_keys || {}
            order.tickets.create!(attributes.slice(:attendee_name, :attendee_email, :tshirt_size, :dietary_preference).merge(ticket_type: type, price_paise: type.price_paise))
          end
        end

        order
      end
    end

    private
      def normalize_items
        selections = @items.map do |item|
          item = item.symbolize_keys
          attendees = Array(item[:attendees])
          quantity = item[:quantity] || attendees.length
          type_id = item[:ticket_type_id] || item[:ticket_type]&.id
          raise InvalidSelection, "ticket type and positive quantity are required" unless type_id && quantity.to_i.positive?

          { ticket_type_id: type_id.to_i, quantity: quantity.to_i, attendees: }
        end
        raise InvalidSelection, "select at least one ticket" if selections.empty?

        selections
      end

      def validate_selections!(selections, ticket_types)
        now = Time.current
        selections.each do |selection|
          type = ticket_types.fetch(selection[:ticket_type_id])
          quantity = selection[:quantity]
          raise InvalidSelection, "#{type.name} is not on sale" unless type.purchasable?(at: now)
          raise InvalidSelection, "#{type.name} quantity is below its minimum" if quantity < type.min_per_order
          raise InvalidSelection, "#{type.name} quantity exceeds its maximum" if type.max_per_order && quantity > type.max_per_order
          raise SoldOut, "#{type.name} does not have #{quantity} tickets available" if type.available_quantity(at: now) < quantity
        end
      end

      def validate_conference_pass!(selections, ticket_types)
        selected_types = selections.map { |selection| ticket_types.fetch(selection[:ticket_type_id]) }
        return unless selected_types.any?(&:requires_conference_pass)
        return if selected_types.any?(&:conference_pass?)
        return if eligible_conference_order?

        raise ConferencePassRequired, "a paid conference pass is required"
      end

      def eligible_conference_order?
        return false if @conference_order_code.blank? || @conference_order_email.blank?

        Order.paid.where(code: @conference_order_code, email: @conference_order_email.strip.downcase)
          .joins(tickets: :ticket_type)
          .where(tickets: { canceled_at: nil })
          .where("ticket_types.slug LIKE 'conference-pass-%'")
          .exists?
      end

      def find_coupon
        return if @coupon_code.blank?

        Coupon.find_by("lower(code) = ?", @coupon_code.strip.downcase) || raise(Coupon::Invalid, "coupon not found")
      end
  end
end
