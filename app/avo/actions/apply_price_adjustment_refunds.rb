class Avo::Actions::ApplyPriceAdjustmentRefunds < Avo::BaseAction
  self.name = "Refund price drop to affected buyers"

  def fields
    field :confirm, as: :boolean, name: "Confirm and process refunds (unchecked = dry run only)", default: false
  end

  def handle(query:, fields:, **)
    return error "Select one ticket type" unless query.one?

    ticket_type = query.first
    by_order = ticket_type.price_adjustment_candidates.includes(:order).group_by(&:order)
    return succeed "No tickets are eligible for a price adjustment refund" if by_order.empty?

    fields[:confirm] ? process_confirmed(by_order) : report_dry_run(by_order)
  end

  private
    def report_dry_run(by_order)
      rows = by_order.filter_map do |order, tickets|
        breakdown = order.price_adjustment_breakdown(tickets.map(&:id))
        breakdown.empty? ? nil : { order: order.code, tickets: breakdown.size, amount_paise: breakdown.values.sum }
      end
      return succeed "No tickets have an outstanding price-drop balance" if rows.empty?

      total = rows.sum { |row| row[:amount_paise] }
      succeed "Dry run — would refund #{rows.sum { |row| row[:tickets] }} ticket(s) across #{rows.size} order(s), ₹#{total / 100.0} total: " \
              "#{rows.map { |row| "#{row[:order]} (#{row[:tickets]} ticket(s), ₹#{row[:amount_paise] / 100.0})" }.join("; ")}"
      keep_modal_open
    end

    def process_confirmed(by_order)
      results = by_order.map do |order, tickets|
        begin
          refund = order.apply_price_adjustment_refund!(tickets.map(&:id))
          { order: order.code, ok: true, amount_paise: refund.amount_paise }
        rescue Refund::AlreadyRefunded, ArgumentError => error
          { order: order.code, ok: false, error: error.message }
        end
      end

      succeeded, failed = results.partition { |result| result[:ok] }
      summary = "Processed #{succeeded.size} order(s), ₹#{succeeded.sum { |result| result[:amount_paise] } / 100.0} total."

      if failed.empty?
        succeed summary
      else
        warn "#{summary} #{failed.size} order(s) failed: #{failed.map { |result| "#{result[:order]} (#{result[:error]})" }.join("; ")}"
        keep_modal_open
      end
    end
end
