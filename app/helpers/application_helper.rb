module ApplicationHelper
  def inr(paise)
    rupees, cents = paise.divmod(100)
    digits = rupees.to_s
    grouped = digits.length > 3 ? "#{digits[0...-3].reverse.scan(/.{1,2}/).join(",").reverse},#{digits[-3..]}" : digits
    "₹#{grouped}#{format(".%02d", cents) unless cents.zero?}"
  end
end
