class Order < ApplicationRecord
  CODE_CHARACTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ379"

  belongs_to :coupon, optional: true
  has_many :tickets, dependent: :restrict_with_exception
  has_many :payment_events, dependent: :restrict_with_exception
  has_many :refunds, dependent: :restrict_with_exception
  has_many :invoices, dependent: :restrict_with_exception

  enum :status, { pending: 0, paid: 1, expired: 2, canceled: 3 }

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :code, presence: true, uniqueness: true, length: { is: 8 }, format: { with: /\A[#{CODE_CHARACTERS}]{8}\z/ }
  validates :email, :buyer_name, presence: true
  validates :billing_state_code, format: { with: /\A\d{2}\z/ }, allow_blank: true
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

    with_lock do
      return if paid?

      update!(status: :paid)
      coupon&.increment!(:uses_count)
      Invoice.issue_for!(self)
    end
  end

  private
    def assign_code
      self.code ||= self.class.generate_code
    end
end
