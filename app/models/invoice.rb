class Invoice < ApplicationRecord
  class LegacySnapshotUnavailable < StandardError; end

  has_one_attached :pdf
  attr_readonly :order_id, :number, :kind, :issued_on, :refers_to_id,
    :buyer_snapshot, :line_items, :snapshot_version, :seller_snapshot, :tax_snapshot

  belongs_to :order
  belongs_to :refers_to, class_name: "Invoice", optional: true
  has_many :credit_notes, class_name: "Invoice", foreign_key: :refers_to_id, dependent: :restrict_with_exception, inverse_of: :refers_to

  enum :kind, { invoice: "invoice", credit_note: "credit_note" }

  validates :number, presence: true, uniqueness: true
  validates :issued_on, presence: true
  validates :refers_to, presence: true, if: :credit_note?
  validate :reference_is_invoice
  validate :validate_snapshot, on: :create
  validate :credit_snapshot_matches_reference, on: :create

  before_update do
    if (changes.keys & self.class.readonly_attributes.to_a).any?
      raise ActiveRecord::ReadOnlyRecord, "issued invoice fields cannot be changed"
    end
  end
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "invoices cannot be destroyed" }

  def attach_pdf!
    return if pdf.attached?
    require_renderable_snapshot!

    pdf.attach(io: StringIO.new(PdfRenderer.render(self, template: :invoice)), filename: "#{number.tr('/', '-')}.pdf", content_type: "application/pdf")
  end

  def self.issue_for!(order, kind: :invoice, refers_to: nil, issued_on: Date.current, line_items: nil)
    existing = order.invoices.invoice.first if kind.to_s == "invoice"
    return existing if existing

    raise ArgumentError, "unsupported document kind" unless %w[invoice credit_note].include?(kind.to_s)
    if kind.to_s == "credit_note"
      raise ArgumentError, "credit note requires an invoice for this order" unless refers_to&.invoice? && refers_to.order_id == order.id
      refers_to.require_renderable_snapshot!
      policy = { seller: refers_to.seller_snapshot, tax: refers_to.tax_snapshot }
      buyer = refers_to.buyer_snapshot
      lines = line_items || refers_to.line_items
      unless lines.present? && lines.uniq.size == lines.size && (lines - refers_to.line_items).empty?
        raise ArgumentError, "credit lines must be unchanged lines from the original invoice"
      end
    else
      policy = InvoicePolicy.snapshot
      buyer = buyer_snapshot(order)
      lines = line_items || line_item_snapshot(order)
      interstate = order.gstin.present? && order.billing_state_code.present? && order.billing_state_code != "27"
      lines = lines.map { |line| line.merge("sac" => policy[:seller].fetch("sac"), "cgst_rate" => interstate ? 0 : 9, "sgst_rate" => interstate ? 0 : 9, "igst_rate" => interstate ? 18 : 0) }
    end

    attempts = 0
    begin
      transaction(requires_new: true) do
        prefix = number_prefix(kind, issued_on)
        create!(
          order:,
          number: next_number(prefix),
          issued_on:,
          buyer_snapshot: buyer,
          line_items: lines,
          snapshot_version: 2,
          seller_snapshot: policy.fetch(:seller),
          tax_snapshot: policy.fetch(:tax),
          kind:,
          refers_to:
        )
      end
    rescue ActiveRecord::RecordNotUnique
      return order.invoices.invoice.first if kind.to_s == "invoice" && order.invoices.invoice.exists?

      attempts += 1
      retry if attempts < 5
      raise
    end
  end

  def self.financial_year(date)
    year = date.month >= 4 ? date.year : date.year - 1
    "#{year}-#{format('%02d', (year + 1) % 100)}"
  end

  def self.number_prefix(kind, date)
    year = date.month >= 4 ? date.year : date.year - 1
    "#{InvoicePolicy.series(kind)}/#{format('%02d%02d', year % 100, (year + 1) % 100)}/"
  end

  def self.next_number(prefix)
    latest = where("number LIKE ?", "#{sanitize_sql_like(prefix)}%").maximum(:number)
    sequence = latest.to_s.split("/").last.to_i + 1
    raise RangeError, "invoice series exhausted; approve a new series" if sequence > 999_999
    "#{prefix}#{format('%06d', sequence)}"
  end

  def self.buyer_snapshot(order)
    order.attributes.slice("email", "buyer_name", "buyer_phone", "gstin", "gst_legal_name", "billing_state_code").merge(
      order.metadata.slice("billing_address", "billing_state_name", "delivery_address")
    )
  end

  def self.line_item_snapshot(order)
    remaining_discount = order.metadata.fetch("discount_paise", 0)
    coupon_ticket_type_id = order.metadata["coupon_ticket_type_id"]

    order.tickets.includes(:ticket_type).order(:id).map do |ticket|
      eligible = coupon_ticket_type_id.blank? || coupon_ticket_type_id.to_i == ticket.ticket_type_id
      discount = eligible ? [ remaining_discount, ticket.price_paise ].min : 0
      remaining_discount -= discount
      total = ticket.price_paise - discount

      {
        "ticket_id" => ticket.id,
        "ticket_type_id" => ticket.ticket_type_id,
        "name" => ticket.ticket_type.name,
        "price_paise" => ticket.price_paise,
        "discount_paise" => discount,
        "total_paise" => total
      }.merge(Gst.breakdown(total, state_code: order.billing_state_code, gstin: order.gstin).stringify_keys)
    end
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "invoices cannot be deleted"
  end

  def require_renderable_snapshot!
    unless snapshot_version == 2
      raise LegacySnapshotUnavailable, "historical invoice has no versioned seller snapshot; retain its archived PDF and request finance review"
    end
  end

  private
    def validate_snapshot
      errors.add(:snapshot_version, "must be 2 for new documents") unless snapshot_version == 2
      errors.add(:number, "must contain at most 16 letters, digits, hyphens or slashes") unless number.to_s.match?(/\A[A-Za-z0-9\/-]{1,16}\z/)
      unless seller_snapshot.is_a?(Hash) && %w[name address gstin sac].all? { |key| seller_snapshot[key].present? }
        errors.add(:seller_snapshot, "must include seller name, address, GSTIN and SAC")
      end
      unless tax_snapshot.is_a?(Hash) && tax_snapshot["policy"] == "domestic-18-v1" && tax_snapshot["reverse_charge"] == false && tax_snapshot["gst_rate"] == 18
        errors.add(:tax_snapshot, "must describe the supported approved policy")
      end
      unless line_items.is_a?(Array) && line_items.any? && line_items.all? { |line| valid_line?(line) }
        errors.add(:line_items, "must contain reconciled amounts, SAC and explicit tax rates")
      end
      unless buyer_snapshot.is_a?(Hash)
        errors.add(:buyer_snapshot, "must contain buyer details")
        return
      end
      return unless line_items.is_a?(Array)

      errors.add(:buyer_snapshot, "requires a buyer name and email") if buyer_snapshot["buyer_name"].blank? || buyer_snapshot["email"].blank?
      total = line_items.sum { |line| line.is_a?(Hash) ? line["total_paise"].to_i : 0 }
      if buyer_snapshot["gstin"].present? || total >= 5_000_000
        %w[billing_address billing_state_code billing_state_name].each do |key|
          errors.add(:buyer_snapshot, "requires #{key}; collect verified buyer details before issuance") if buyer_snapshot[key].blank?
        end
      end
    end

    def valid_line?(line)
      return false unless line.is_a?(Hash) && line["name"].present? && line["sac"].to_s.match?(/\A\d{6}\z/)
      keys = %w[price_paise discount_paise total_paise taxable cgst sgst igst]
      return false unless keys.all? { |key| line[key].is_a?(Integer) && line[key] >= 0 }
      rates = line.values_at("cgst_rate", "sgst_rate", "igst_rate")
      return false unless [ [ 9, 9, 0 ], [ 0, 0, 18 ] ].include?(rates)
      expected = Gst.breakdown(line["total_paise"], state_code: rates.last == 18 ? "29" : "27", gstin: "present").stringify_keys
      line["price_paise"] - line["discount_paise"] == line["total_paise"] && expected.all? { |key, value| line[key] == value }
    end

    def credit_snapshot_matches_reference
      return unless credit_note? && refers_to

      unless refers_to.snapshot_version == 2 && seller_snapshot == refers_to.seller_snapshot &&
          buyer_snapshot == refers_to.buyer_snapshot && tax_snapshot == refers_to.tax_snapshot &&
          line_items.is_a?(Array) && line_items.any? && line_items.uniq.size == line_items.size &&
          (line_items - refers_to.line_items).empty?
        errors.add(:refers_to, "requires original versioned snapshots and unchanged credit lines")
      end
    end

    def reference_is_invoice
      errors.add(:refers_to, "must be an invoice for the same order") if refers_to && (!refers_to.invoice? || refers_to.order_id != order_id)
    end
end
