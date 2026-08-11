class Ticket < ApplicationRecord
  TSHIRT_SIZES = %w[XS S M L XL XXL 3XL].freeze

  class AlreadyCheckedIn < StandardError
    attr_reader :checked_in_at

    def initialize(checked_in_at)
      @checked_in_at = checked_in_at
      super("already checked in at #{checked_in_at}")
    end
  end

  class Canceled < StandardError; end

  belongs_to :order
  belongs_to :ticket_type

  has_one_attached :pdf

  has_secure_token :secret, length: 24
  has_secure_token :claim_token, length: 24

  normalizes :attendee_email, with: ->(email) { email.strip.downcase }

  scope :awaiting_details, -> {
    where(canceled_at: nil)
      .where.not(attendee_email: [ nil, "" ])
      .where("tshirt_size IS NULL OR tshirt_size = ''")
  }

  # Passes that count as "going": paid order, not canceled. Used for the
  # public attendee count (social proof) and anywhere we tally real attendees.
  scope :confirmed, -> { joins(:order).merge(Order.paid).where(canceled_at: nil) }

  # Distinct emails of attendees holding a paid, non-canceled ticket — used for broadcast emails.
  def self.broadcast_recipients
    joins(:order).merge(Order.paid)
      .where(canceled_at: nil)
      .where.not(attendee_email: [ nil, "" ])
      .distinct
      .pluck(:attendee_email)
  end

  validates :price_paise, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :secret, presence: true, uniqueness: true
  validates :claim_token, presence: true
  validates :attendee_name, :attendee_email, presence: true, if: :assigned_at?
  validates :attendee_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  def assigned?
    attendee_name.present? && attendee_email.present?
  end

  def details_pending?
    assigned? && !canceled_at? && tshirt_size.blank?
  end

  def request_details!
    raise Canceled, "canceled ticket cannot be nudged" if canceled_at?
    raise ArgumentError, "ticket is not assigned to an attendee yet" unless assigned?

    OrderMailer.complete_details(self).deliver_later
  end

  def assign!(attendee_name:, attendee_email:, dietary_preference: nil, childcare_needed: false, tshirt_size: nil)
    raise Canceled, "canceled ticket cannot be assigned" if canceled_at?

    update!(attendee_name:, attendee_email:, dietary_preference:, childcare_needed:, tshirt_size:, assigned_at: Time.current)
    attach_pdf!
    OrderMailer.ticket(self).deliver_later
  end

  def attach_pdf!
    pdf.attach(io: StringIO.new(PdfRenderer.render(self, template: :ticket)), filename: "DQOR-ticket-#{id}.pdf", content_type: "application/pdf")
  end

  def check_in!(date)
    with_lock do
      raise Canceled, "canceled ticket cannot be checked in" if canceled_at?

      key = date.to_date.iso8601
      raise AlreadyCheckedIn, checked_in_at.fetch(key) if checked_in_at.key?(key)

      timestamp = Time.current.iso8601
      update!(checked_in_at: checked_in_at.merge(key => timestamp))
      timestamp
    end
  end
end
