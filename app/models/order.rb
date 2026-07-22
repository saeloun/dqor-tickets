class Order < ApplicationRecord
  require "csv"

  CODE_CHARACTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ379"

  class InsufficientAvailability < StandardError; end
  class InvalidTransition < StandardError; end

  belongs_to :coupon, optional: true
  has_many :tickets, dependent: :restrict_with_exception
  has_many :payment_events, dependent: :restrict_with_exception
  has_many :refunds, dependent: :restrict_with_exception
  has_many :invoices, dependent: :restrict_with_exception

  enum :status, { pending: 0, paid: 1, expired: 2, canceled: 3 }

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :gstin, with: ->(gstin) { gstin.strip.upcase }

  validates :code, presence: true, uniqueness: true, length: { is: 8 }, format: { with: /\A[#{CODE_CHARACTERS}]{8}\z/ }
  validates :email, :buyer_name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :gstin, format: { with: /\A\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]\z/ }, allow_blank: true
  validates :billing_state_code, format: { with: /\A\d{2}\z/ }, allow_blank: true
  validates :billing_state_code, presence: true, if: -> { gstin.present? }
  validates :total_paise, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :assign_code, on: :create

  scope :reserving_inventory, ->(at = Time.current) { paid.or(pending.where("expires_at > ?", at)) }
  scope :overdue, ->(at = Time.current) { pending.where("expires_at <= ?", at) }
  scope :reconcilable, ->(at = 2.minutes.ago) { pending.where.not(razorpay_order_id: nil).where(created_at: ...at) }

  def self.generate_code
    loop do
      code = Array.new(8) { CODE_CHARACTERS[SecureRandom.random_number(CODE_CHARACTERS.length)] }.join
      return code unless exists?(code: code)
    end
  end

  def self.expire_overdue!(at: Time.current)
    overdue(at).update_all(status: statuses[:expired], updated_at: at)
  end

  def self.reconcile_pending_payments!
    reconcilable.find_each(&:reconcile_payment!)
  end

  def self.issue_comps!(emails:, attendee_names: "")
    email_list = emails.to_s.lines.map(&:strip).compact_blank
    names = attendee_names.to_s.lines.map(&:strip)
    raise ArgumentError, "enter at least one email" if email_list.empty?

    ticket_type = TicketType.find_by!(slug: "complimentary-pass", hidden: true)

    orders = transaction do
      email_list.map.with_index do |email, index|
        create!(email:, buyer_name: names[index].presence || email, total_paise: 0, expires_at: 30.minutes.from_now).tap do |order|
          order.tickets.create!(ticket_type:, price_paise: 0, attendee_name: names[index].presence || email, attendee_email: email)
          order.complete_comp!
        end
      end
    end
    orders.each { |order| DeliverOrderConfirmationJob.perform_later(order) }
    orders
  end

  def self.orders_csv(relation = all)
    CSV.generate(headers: true) do |csv|
      csv << %w[code status buyer_name email buyer_phone tickets subtotal_paise discount_paise total_paise taxable_paise cgst_paise sgst_paise igst_paise coupon gstin gst_legal_name billing_state_code tshirt_sizes dietary_preferences]
      relation.includes(:coupon, tickets: :ticket_type).find_each do |order|
        lines = Invoice.line_item_snapshot(order)
        csv << [
          order.code,
          order.status,
          order.buyer_name,
          order.email,
          order.buyer_phone,
          order.tickets.map { |ticket| ticket.ticket_type.name }.join(" | "),
          order.tickets.sum(&:price_paise),
          order.metadata.fetch("discount_paise", 0),
          order.total_paise,
          lines.sum { |line| line.fetch("taxable") },
          lines.sum { |line| line.fetch("cgst") },
          lines.sum { |line| line.fetch("sgst") },
          lines.sum { |line| line.fetch("igst") },
          order.coupon&.code,
          order.gstin,
          order.gst_legal_name,
          order.billing_state_code,
          order.tickets.filter_map(&:tshirt_size).join(" | "),
          order.tickets.filter_map(&:dietary_preference).join(" | ")
        ]
      end
    end
  end

  def self.attendees_csv(relation = all)
    CSV.generate(headers: true) do |csv|
      csv << %w[order_code order_status buyer_name buyer_email ticket_id ticket_type attendee_name attendee_email price_paise total_paise taxable_paise cgst_paise sgst_paise igst_paise coupon tshirt_size dietary_preference]
      relation.includes(:coupon, tickets: :ticket_type).find_each do |order|
        lines = Invoice.line_item_snapshot(order).index_by { |line| line.fetch("ticket_id") }
        order.tickets.each do |ticket|
          line = lines.fetch(ticket.id)
          csv << [
            order.code,
            order.status,
            order.buyer_name,
            order.email,
            ticket.id,
            ticket.ticket_type.name,
            ticket.attendee_name,
            ticket.attendee_email,
            ticket.price_paise,
            line.fetch("total_paise"),
            line.fetch("taxable"),
            line.fetch("cgst"),
            line.fetch("sgst"),
            line.fetch("igst"),
            order.coupon&.code,
            ticket.tshirt_size,
            ticket.dietary_preference
          ]
        end
      end
    end
  end

  def mark_paid!(payment_event)
    raise ArgumentError, "payment event belongs to another order" unless payment_event.order_id == id
    raise ArgumentError, "payment amount does not match order total" unless payment_event.amount_paise == total_paise

    with_lock do
      return false if paid?

      ensure_payable!
      update!(status: :paid)
      coupon&.increment!(:uses_count)
      Invoice.issue_for!(self)
      true
    end
  end

  def create_razorpay_order!
    return self if razorpay_order_id?
    return complete_comp! if total_paise < 100

    razorpay_order = Razorpay::Order.create(amount: total_paise, currency: "INR", receipt: code)
    update!(razorpay_order_id: razorpay_order.id)
    payment_events.create!(
      razorpay_event_id: "order_created_#{razorpay_order.id}",
      kind: "order_created",
      amount_paise: total_paise,
      raw: { "razorpay_order_id" => razorpay_order.id }
    )
    self
  end

  def complete_comp!
    payment_event = payment_events.create_or_find_by!(razorpay_event_id: "comp_#{code}") do |event|
      event.kind = "comp"
      event.amount_paise = total_paise
    end

    mark_paid!(payment_event)
  end

  def reconcile_payment!
    return unless pending? && razorpay_order_id?

    payment = Array(Razorpay::Order.fetch(razorpay_order_id).payments.items).find { |item| item["captured"] || item["status"] == "captured" }
    unless payment
      payment_events.create!(
        razorpay_event_id: "polling_checked_#{SecureRandom.uuid}",
        kind: "polling_checked",
        amount_paise: total_paise
      )
      return
    end

    payment_event = payment_events.create_or_find_by!(razorpay_event_id: "reconcile_#{payment.fetch("id")}") do |event|
      event.razorpay_payment_id = payment.fetch("id") unless payment_events.exists?(razorpay_payment_id: payment.fetch("id"))
      event.kind = "reconciled_captured"
      event.amount_paise = payment.fetch("amount", total_paise)
      event.raw = payment
    end
    ConfirmOrderJob.perform_now(razorpay_order_id, payment_event.id)
  rescue Razorpay::Error => error
    record_polling_failure(error)
    raise ApplicationJob::TransientRazorpayError, error.message if error.status.to_i == 429 || error.status.to_i >= 500
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, SocketError => error
    record_polling_failure(error)
    raise
  end

  def refund_tickets!(ticket_ids)
    selected_ids = Array(ticket_ids).map { |id| Integer(id) }.uniq
    selected_tickets = tickets.where(id: selected_ids, canceled_at: nil)
    raise ArgumentError, "select at least one refundable ticket" unless selected_tickets.count == selected_ids.size && selected_ids.any?

    lines = invoices.invoice.sole.line_items.select { |line| selected_ids.include?(line.fetch("ticket_id")) }
    amount_paise = lines.sum { |line| line.fetch("total_paise") }
    payment_id = if amount_paise.positive?
      payment_events.order(created_at: :desc).filter_map do |event|
        event.razorpay_payment_id || event.raw.dig("payload", "payment", "entity", "id")
      end.first || raise(ArgumentError, "order has no Razorpay payment")
    end

    refund = refunds.create!(amount_paise:, ticket_ids: selected_ids, status: "initiated")
    if amount_paise.zero?
      event = payment_events.create!(razorpay_event_id: "free_refund_#{refund.id}", kind: "refund.processed", amount_paise: 0)
      ProcessRefundJob.perform_now(refund.id, event.id)
    else
      InitiateRefundJob.perform_later(refund, payment_id)
    end

    refund
  end

  def confirm_from_razorpay_if_stalled!
    callback = payment_events.find_by(kind: "callback_verified")
    return unless pending? && callback&.created_at && callback.created_at < 30.seconds.ago
    return unless claim_fallback_check!

    payment = Array(Razorpay::Order.fetch(razorpay_order_id).payments.items).find { |item| item["captured"] || item["status"] == "captured" }
    unless payment
      payment_events.create!(
        razorpay_event_id: "polling_checked_#{SecureRandom.uuid}",
        kind: "polling_checked",
        amount_paise: total_paise
      )
      return
    end

    payment_event = payment_events.create_or_find_by!(razorpay_event_id: "fallback_#{payment.fetch("id")}") do |event|
      event.kind = "fallback_captured"
      event.amount_paise = payment.fetch("amount", total_paise)
      event.raw = payment
    end
    ConfirmOrderJob.perform_later(razorpay_order_id, payment_event.id)
  rescue Razorpay::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, SocketError => error
    record_polling_failure(error)
    Rails.logger.error("Razorpay fallback failed for order_id=#{id}: #{error.message}")
  end

  def deliver_confirmation!(documents_pending: false)
    attach_documents! unless documents_pending

    with_lock do
      return false if metadata["confirmation_enqueued_at"]

      OrderMailer.confirmation(self, documents_pending:).deliver_later
      update!(metadata: metadata.merge("confirmation_enqueued_at" => Time.current.iso8601))
    end

    true
  end

  def resend_confirmation!
    attach_documents!
    OrderMailer.confirmation(self).deliver_later
  end

  def attach_documents!
    invoices.invoice.first&.attach_pdf!
  end

  private
    def record_polling_failure(error)
      payment_events.create!(
        razorpay_event_id: "polling_check_failed_#{SecureRandom.uuid}",
        kind: "polling_check_failed",
        level: "warn",
        amount_paise: total_paise,
        raw: { "error" => error.class.name, "message" => error.message }
      )
    end

    def ensure_payable!
      raise InvalidTransition, "only pending or expired orders can be paid" unless pending? || expired?
      return unless expired? || (expires_at && expires_at <= Time.current)

      quantities = tickets.group(:ticket_type_id).count
      ticket_types = TicketType.where(id: quantities.keys).order(:id).lock.index_by(&:id)
      unavailable = quantities.any? { |ticket_type_id, quantity| ticket_types.fetch(ticket_type_id).available_quantity < quantity }
      raise InsufficientAvailability, "ticket inventory is no longer available" if unavailable
    end

    def claim_fallback_check!
      with_lock do
        return false if metadata["fallback_checked_at"]

        update!(metadata: metadata.merge("fallback_checked_at" => Time.current.iso8601))
        true
      end
    end

    def assign_code
      self.code ||= self.class.generate_code
    end
end
