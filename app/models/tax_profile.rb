class TaxProfile < ApplicationRecord
  GSTIN_CHARACTERS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  GSTIN_FORMAT = /\A\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]\z/

  belongs_to :organizer
  belongs_to :event, optional: true

  enum :invoice_timing, { immediate: "immediate", voucher_then_invoice: "voucher_then_invoice" }, validate: true

  normalizes :gstin, with: ->(gstin) { gstin.strip.upcase }

  validates :legal_name, :registered_state_code, :address, :country, :sac_code, :invoice_prefix, :cn_prefix, presence: true
  validates :registered_state_code, format: { with: /\A\d{2}\z/ }
  validates :country, format: { with: /\A[A-Z]{2}\z/ }
  validates :tax_rate_bp, numericality: { only_integer: true, in: 0..10_000 }
  validate :gstin_has_valid_checksum

  private
    def gstin_has_valid_checksum
      return if gstin.blank?

      unless GSTIN_FORMAT.match?(gstin) && gstin.last == gstin_checksum
        errors.add(:gstin, "is invalid")
      end
    end

    def gstin_checksum
      sum = gstin.first(14).reverse.chars.each_with_index.sum do |character, index|
        product = GSTIN_CHARACTERS.index(character) * (index.even? ? 2 : 1)
        product.div(36) + product.modulo(36)
      end
      GSTIN_CHARACTERS[(36 - sum.modulo(36)).modulo(36)]
    end
end
