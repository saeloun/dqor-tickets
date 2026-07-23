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

  validates :price_paise, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :secret, presence: true, uniqueness: true
  validates :claim_token, presence: true
  validates :attendee_name, :attendee_email, presence: true, if: :assigned_at?
  validates :attendee_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  def assigned?
    attendee_name.present? && attendee_email.present?
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
