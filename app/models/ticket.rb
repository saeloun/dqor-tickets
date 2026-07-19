class Ticket < ApplicationRecord
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

  has_secure_token :secret, length: 24

  validates :price_paise, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :secret, presence: true, uniqueness: true

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
