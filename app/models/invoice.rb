class Invoice < ApplicationRecord
  has_one_attached :pdf

  belongs_to :order
  belongs_to :refers_to, class_name: "Invoice", optional: true
  has_many :credit_notes, class_name: "Invoice", foreign_key: :refers_to_id, dependent: :restrict_with_exception, inverse_of: :refers_to

  enum :kind, { invoice: "invoice", credit_note: "credit_note" }

  validates :number, presence: true, uniqueness: true
  validates :issued_on, presence: true
  validates :refers_to, presence: true, if: :credit_note?
  validate :reference_is_invoice

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "invoices cannot be destroyed" }

  def attach_pdf!
    pdf.attach(io: StringIO.new(InvoicePdf.new(self).render), filename: "#{number.tr('/', '-')}.pdf", content_type: "application/pdf") unless pdf.attached?
  end

  def self.issue_for!(order, kind: :invoice, refers_to: nil, issued_on: Date.current, line_items: nil)
    existing = order.invoices.invoice.first if kind.to_s == "invoice"
    return existing if existing

    attempts = 0
    begin
      transaction(requires_new: true) do
        prefix = number_prefix(kind, issued_on)
        create!(
          order:,
          number: next_number(prefix),
          issued_on:,
          buyer_snapshot: buyer_snapshot(order),
          line_items: line_items || line_item_snapshot(order),
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
    "#{kind.to_s == 'credit_note' ? 'DQOR-CN' : 'DQOR'}/#{financial_year(date)}/"
  end

  def self.next_number(prefix)
    latest = where("number LIKE ?", "#{sanitize_sql_like(prefix)}%").maximum(:number)
    "#{prefix}#{format('%04d', latest.to_s.split('/').last.to_i + 1)}"
  end

  def self.buyer_snapshot(order)
    order.attributes.slice("email", "buyer_name", "buyer_phone", "gstin", "gst_legal_name", "billing_state_code")
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

  private
    def reference_is_invoice
      errors.add(:refers_to, "must be an invoice") if refers_to && !refers_to.invoice?
    end
end
