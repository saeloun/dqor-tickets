module Gst
  module_function

  def breakdown(price_paise, state_code:, gstin: nil)
    taxable = (price_paise / 1.18).round
    tax = price_paise - taxable

    if gstin.blank? || state_code.blank? || state_code.to_s == "27"
      sgst = tax / 2
      { taxable:, cgst: tax - sgst, sgst:, igst: 0 }
    else
      { taxable:, cgst: 0, sgst: 0, igst: tax }
    end
  end
end
