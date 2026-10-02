# Explicit approval gate for the existing domestic, GST-inclusive 18% calculation.
# This is not a general tax engine; unsupported policies must fail closed.
class InvoicePolicy
  class NotConfigured < StandardError; end

  def self.snapshot
    unless ENV["INVOICE_POLICY_VERSION"] == "domestic-18-v1" && ENV["INVOICE_REVERSE_CHARGE"] == "false"
      raise NotConfigured, "approve domestic-18-v1 and explicitly configure reverse charge before issuing invoices"
    end

    seller = %w[name address gstin sac].to_h do |key|
      value = ENV["SELLER_#{key.upcase}"].presence
      raise NotConfigured, "SELLER_#{key.upcase} is required" unless value
      [ key, value ]
    end
    unless seller["gstin"].match?(/\A27[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]\z/) && seller["sac"].match?(/\A\d{6}\z/)
      raise NotConfigured, "current tax engine requires a Maharashtra seller GSTIN and a six-digit SAC"
    end
    { seller: seller, tax: { "policy" => "domestic-18-v1", "reverse_charge" => false, "gst_rate" => 18 } }
  end

  def self.series(kind)
    key = kind.to_s == "credit_note" ? "CREDIT_NOTE_SERIES" : "INVOICE_SERIES"
    series = ENV[key].to_s
    configured_series = ENV.values_at("INVOICE_SERIES", "CREDIT_NOTE_SERIES")
    unless configured_series.all? { |value| value.to_s.match?(/\A[A-Z0-9]{1,4}\z/) } && configured_series.uniq.size == 2
      raise NotConfigured, "configure distinct INVOICE_SERIES and CREDIT_NOTE_SERIES (1–4 uppercase letters/digits)"
    end
    series
  end
end
