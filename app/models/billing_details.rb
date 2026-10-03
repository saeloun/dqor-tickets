class BillingDetails
  include ActiveModel::Model

  class Invalid < StandardError; end
  class Locked < StandardError; end
  class Stale < StandardError; end

  FIELDS = %w[billing_address billing_state_name delivery_address].freeze
  ORDER_FIELDS = %w[billing_state_code gst_legal_name].freeze
  attr_accessor(*FIELDS, :billing_state_code, :gstin, :gst_legal_name, :total_paise, :requested)

  validates :gst_legal_name, length: { maximum: 200 }
  validates :billing_address, length: { maximum: 1000 }
  validates :delivery_address, length: { maximum: 1000 }
  validates :billing_state_name, length: { maximum: 100 }
  validates :billing_address, :billing_state_name, :billing_state_code, presence: true, if: :required?
  validates :billing_state_code, format: { with: /\A\d{2}\z/ }, allow_blank: true
  validates :gst_legal_name, presence: true, if: -> { gstin.present? }
  validate :state_matches_registration

  def required?
    gstin.present? || total_paise.to_i >= 5_000_000 || ActiveModel::Type::Boolean.new.cast(requested) ||
      FIELDS.any? { |key| public_send(key).present? }
  end

  def metadata!
    raise Invalid, errors.full_messages.to_sentence unless valid?

    FIELDS.to_h { |key| [ key, public_send(key).to_s.strip ] }.merge("billing_details_requested" => !!required?)
  end

  def self.for_order(order, attributes = {})
    LegacyCommerce.assert!(order)
    new(order.metadata.slice(*FIELDS).merge(
      "billing_state_code" => order.billing_state_code, "gstin" => order.gstin,
      "gst_legal_name" => order.gst_legal_name, "total_paise" => order.total_paise,
      "requested" => order.metadata["billing_details_requested"]
    ).merge(attributes.stringify_keys.slice(*FIELDS, *ORDER_FIELDS)))
  end

  def self.update_order!(order, attributes, source:, revision:)
    LegacyCommerce.assert!(order)
    order.with_lock do
      raise Locked, "An invoice has already been issued; billing snapshots cannot be rewritten." if order.invoices.exists?
      raise Stale, "Billing details changed. Reload before saving." unless revision.to_s == order.metadata.fetch("billing_revision", 0).to_s
      details = for_order(order, attributes)
      if order.billing_state_code.present? && details.billing_state_code != order.billing_state_code
        raise Locked, "The captured billing state cannot be changed here; request finance review."
      end
      if order.gst_legal_name.present? && details.gst_legal_name != order.gst_legal_name
        raise Locked, "The captured registered name cannot be changed here; request finance review."
      end
      metadata = details.metadata!
      audit = { "at" => Time.current.iso8601, "source" => source, "fields" => (FIELDS + ORDER_FIELDS) }
      order.update!(billing_state_code: details.billing_state_code, gst_legal_name: details.gst_legal_name, metadata: order.metadata.merge(metadata).merge(
        "billing_revision" => order.metadata.fetch("billing_revision", 0).to_i + 1,
        "billing_request_nonce" => nil,
        "billing_updates" => order.metadata.fetch("billing_updates", []) + [ audit ]
      ))
    end
  end

  private
    def state_matches_registration
      if gstin.present? && billing_state_code.present? && gstin.to_s.first(2) != billing_state_code
        errors.add(:billing_state_code, "must match the GSTIN state prefix")
      end
    end
end
