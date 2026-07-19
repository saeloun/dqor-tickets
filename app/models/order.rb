class Order < ApplicationRecord
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

  def self.generate_code
    loop do
      code = Array.new(8) { CODE_CHARACTERS[SecureRandom.random_number(CODE_CHARACTERS.length)] }.join
      return code unless exists?(code: code)
    end
  end

  def self.expire_overdue!(at: Time.current)
    overdue(at).update_all(status: statuses[:expired], updated_at: at)
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

    razorpay_order = Razorpay::Order.create(amount: total_paise, currency: "INR", receipt: code)
    update!(razorpay_order_id: razorpay_order.id)
    self
  end

  def complete_comp!
    payment_event = payment_events.create_or_find_by!(razorpay_event_id: "comp_#{code}") do |event|
      event.kind = "comp"
      event.amount_paise = 0
    end

    mark_paid!(payment_event)
    deliver_confirmation!
  end

  def confirm_from_razorpay_if_stalled!
    callback = payment_events.find_by(kind: "callback_verified")
    return unless pending? && callback&.created_at && callback.created_at < 30.seconds.ago
    return unless claim_fallback_check!

    payment = Array(Razorpay::Order.fetch(razorpay_order_id).payments.items).find { |item| item["captured"] || item["status"] == "captured" }
    return unless payment

    payment_event = payment_events.create_or_find_by!(razorpay_event_id: "fallback_#{payment.fetch("id")}") do |event|
      event.kind = "fallback_captured"
      event.amount_paise = payment.fetch("amount", total_paise)
      event.raw = payment
    end
    ConfirmOrderJob.perform_later(razorpay_order_id, payment_event.id)
  rescue Razorpay::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => error
    Rails.logger.error("Razorpay fallback failed for order_id=#{id}: #{error.message}")
  end

  def deliver_confirmation!
    with_lock do
      return false if metadata["confirmation_enqueued_at"]

      attach_documents!
      update!(metadata: metadata.merge("confirmation_enqueued_at" => Time.current.iso8601))
      OrderMailer.confirmation(self).deliver_later
      true
    end
  end

  def attach_documents!
    invoices.invoice.sole.attach_pdf!
    tickets.includes(:ticket_type).find_each(&:attach_pdf!)
  end

  private
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
