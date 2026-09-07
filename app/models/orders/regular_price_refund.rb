module Orders
  class RegularPriceRefund
    OLD_PRICE_PAISE = 550_000
    REFUND_PAISE = 200_000
    TICKET_SLUG = "conference-pass-regular"
    REFERENCE_PREFIX = "regular-price-5500-to-3500"

    def self.eligible_orders
      ticket_orders = Ticket.joins(:ticket_type)
        .where(ticket_types: { slug: TICKET_SLUG }, tickets: { price_paise: OLD_PRICE_PAISE, canceled_at: nil })
        .select(:order_id)
      Order.paid.where(id: ticket_orders)
    end

    def initialize(order)
      @order = order
    end

    def call
      refund, gateway_payment_id = @order.with_lock do
        if existing_refund
          raise ArgumentError, "price adjustment for order #{@order.code} failed" if existing_refund.failed?

          gateway_payment_id = payment_id unless existing_refund.razorpay_refund_id? || existing_refund.processed?
          [ existing_refund, gateway_payment_id ]
        else
          raise ArgumentError, "only a paid order can receive a price adjustment" unless @order.paid?
          lines = line_items
          raise ArgumentError, "order #{@order.code} has no eligible tickets" if lines.empty?

          gateway_payment_id = payment_id
          refund = @order.refunds.create!(
            amount_paise: lines.sum { |line| line.fetch("total_paise") },
            ticket_ids: lines.pluck("ticket_id"),
            line_items: lines,
            reason: "price_adjustment",
            reference:,
            status: "initiated"
          )
          [ refund, gateway_payment_id ]
        end
      end
      InitiateRefundJob.perform_later(refund, gateway_payment_id) if gateway_payment_id
      refund
    end

    def amount_paise
      line_items.sum { |line| line.fetch("total_paise") }
    end

    def line_items
      invoice = @order.invoices.invoice.first or raise ArgumentError, "order #{@order.code} has no invoice"
      blocked_ids = @order.refunds.where.not(status: "failed").flat_map(&:ticket_ids)
      tickets = @order.tickets.joins(:ticket_type)
        .where(ticket_types: { slug: TICKET_SLUG }, tickets: { price_paise: OLD_PRICE_PAISE, canceled_at: nil })
        .where.not(id: blocked_ids)
        .index_by(&:id)

      invoice.line_items.filter_map do |line|
        next unless tickets.key?(line.fetch("ticket_id"))

        total = [ REFUND_PAISE, line.fetch("total_paise") ].min
        line.slice("ticket_id", "ticket_type_id", "name").merge(
          "name" => "#{line.fetch("name")} — price adjustment",
          "price_paise" => REFUND_PAISE,
          "discount_paise" => REFUND_PAISE - total,
          "total_paise" => total
        ).merge(Gst.breakdown(total, state_code: @order.billing_state_code, gstin: @order.gstin).stringify_keys)
      end
    end

    def reference
      "#{REFERENCE_PREFIX}:#{@order.id}"
    end

    private
      def existing_refund
        @order.refunds.find_by(reference:)
      end

      def payment_id
        ids = @order.payment_events.order(created_at: :desc).filter_map do |event|
          event.razorpay_payment_id || event.raw.dig("payload", "payment", "entity", "id")
        end.uniq
        return ids.sole if ids.one?

        raise ArgumentError, "order #{@order.code} does not have exactly one Razorpay payment"
      end
  end
end
