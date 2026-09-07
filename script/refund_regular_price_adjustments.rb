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
  amount = adjustment.amount_paise
  next if amount.zero?

  refund = adjustment.call if execute
  count += 1
  total += amount
  puts [ execute ? "execute" : "preview", order.code, adjustment.line_items.pluck("ticket_id").join(","), amount, refund&.id || "eligible" ].join("\t")
rescue ArgumentError => error
  puts [ "skip", order.code, "", 0, error.message ].join("\t")
end

puts "summary\torders=#{count}\tamount_paise=#{total}"
