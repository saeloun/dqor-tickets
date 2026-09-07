# Preview:
#   bin/rails runner script/refund_regular_price_adjustments.rb
# Execute all:
#   EXECUTE=regular-price-5500-to-3500 bin/rails runner script/refund_regular_price_adjustments.rb
# Execute one canary:
#   EXECUTE=regular-price-5500-to-3500 ORDER_CODE=XXXXXXXX bin/rails runner script/refund_regular_price_adjustments.rb

execute = ENV["EXECUTE"] == Orders::RegularPriceRefund::REFERENCE_PREFIX
abort "Invalid EXECUTE value" if ENV["EXECUTE"].present? && !execute

orders = Orders::RegularPriceRefund.eligible_orders.order(:id)
orders = orders.where(code: ENV["ORDER_CODE"]) if ENV["ORDER_CODE"].present?
count = 0
total = 0

puts "mode\torder\ttickets\tamount_paise\tresult"
orders.find_each do |order|
  adjustment = Orders::RegularPriceRefund.new(order)
  existing = order.refunds.find_by(reference: adjustment.reference)
  lines = adjustment.line_items unless existing
  amount = existing&.amount_paise || lines.sum { |line| line.fetch("total_paise") }
  next if amount.zero? && !existing

  refund = adjustment.call if execute && (!existing || existing.initiated? && !existing.razorpay_refund_id?)
  count += 1 unless existing
  total += amount unless existing
  puts [ execute ? "execute" : "preview", order.code, existing&.ticket_ids&.join(",") || lines.pluck("ticket_id").join(","), amount, refund&.id || existing&.status || "eligible" ].join("\t")
rescue ArgumentError => error
  puts [ "skip", order.code, "", 0, error.message ].join("\t")
end

puts "summary\torders=#{count}\tamount_paise=#{total}"
