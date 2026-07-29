class BackfillDqorTenancy < ActiveRecord::Migration[8.1]
  class BackfillRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class DqorAccount < BackfillRecord
    self.table_name = "accounts"
  end

  class DqorOrganizer < BackfillRecord
    self.table_name = "organizers"
  end

  class DqorTaxProfile < BackfillRecord
    self.table_name = "tax_profiles"
  end

  class DqorEvent < BackfillRecord
    self.table_name = "events"
  end

  class DqorInvoice < BackfillRecord
    self.table_name = "invoices"
  end

  class DqorInvoiceSequence < BackfillRecord
    self.table_name = "invoice_sequences"
  end

  SCOPED_TABLES = %w[ticket_types coupons orders tickets invoices refunds payment_events].freeze

  def up
    account = DqorAccount.find_or_initialize_by(name: "Saeloun")
    account.update!(country: "IN", status: "active")

    organizer = DqorOrganizer.find_or_initialize_by(slug: "dqor")
    organizer.update!(
      account_id: account.id,
      name: "Deccan Queen on Rails",
      default_currency: "INR",
      default_timezone: "Asia/Kolkata",
      payout_mode: "direct",
      status: "active"
    )

    event = DqorEvent.find_or_initialize_by(organizer_id: organizer.id, slug: "2026")
    event.update!(
      title: "Deccan Queen on Rails 2026",
      status: "published",
      format: "in_person",
      starts_at: Time.new(2026, 10, 8, 0, 0, 0, "+05:30"),
      ends_at: Time.new(2026, 10, 11, 23, 59, 59, "+05:30"),
      timezone: "Asia/Kolkata",
      venue_name: "Hyatt Regency Pune",
      venue_address: "Nagar Road, Pune, Maharashtra",
      venue_state_code: "27",
      currency: "INR",
      visibility: "public",
      brand: {
        "name" => "Deccan Queen on Rails",
        "short_name" => "DQOR",
        "location" => "Pune",
        "station_code" => "Pune JN"
      },
      settings: {}
    )

    tax_profile = DqorTaxProfile.find_or_initialize_by(organizer_id: organizer.id, event_id: nil)
    tax_profile.update!(
      country: "IN",
      gstin: ENV["SELLER_GSTIN"],
      legal_name: ENV.fetch("SELLER_NAME", "Saeloun Software Pvt Ltd"),
      registered_state_code: "27",
      address: ENV.fetch("SELLER_ADDRESS", "Pune, Maharashtra"),
      sac_code: ENV.fetch("SELLER_SAC", "998596"),
      tax_rate_bp: 1800,
      tax_inclusive: true,
      invoice_prefix: "DQOR/",
      cn_prefix: "DQOR-CN/",
      invoice_timing: "immediate"
    )

    SCOPED_TABLES.each do |table|
      backfill_class(table).where(event_id: nil).in_batches.update_all(event_id: event.id)
    end
    %w[orders invoices].each do |table|
      backfill_class(table).where(organizer_id: nil).in_batches.update_all(organizer_id: organizer.id)
    end

    seed_invoice_sequences(organizer)
  end

  def down
    organizer = DqorOrganizer.find_by(slug: "dqor")
    event = organizer && DqorEvent.find_by(organizer_id: organizer.id, slug: "2026")

    if event
      SCOPED_TABLES.each do |table|
        backfill_class(table).where(event_id: event.id).in_batches.update_all(event_id: nil)
      end
    end
    if organizer
      %w[orders invoices].each do |table|
        backfill_class(table).where(organizer_id: organizer.id).in_batches.update_all(organizer_id: nil)
      end
      DqorInvoiceSequence.where(organizer_id: organizer.id).delete_all
      DqorTaxProfile.where(organizer_id: organizer.id).delete_all
      event&.delete
      account_id = organizer.account_id
      organizer.delete
      DqorAccount.where(id: account_id).where.not(id: DqorOrganizer.select(:account_id)).delete_all
    end
  end

  private
    def backfill_class(table)
      Class.new(BackfillRecord) { self.table_name = table }
    end

    def seed_invoice_sequences(organizer)
      maxima = DqorInvoice.find_each.each_with_object({}) do |invoice, result|
        number = Integer(invoice.number.to_s.split("/").last, exception: false)
        next unless number

        series = invoice.kind == "credit_note" ? "credit_note" : "invoice"
        date = invoice.issued_on
        year = date.month >= 4 ? date.year : date.year - 1
        key = [ series, "#{year}-#{format('%02d', (year + 1) % 100)}" ]
        result[key] = [ result.fetch(key, 0), number ].max
      end

      maxima.each do |(series, fiscal_year), last_number|
        sequence = DqorInvoiceSequence.find_or_initialize_by(organizer_id: organizer.id, series:, fiscal_year:)
        sequence.last_number = [ sequence.last_number.to_i, last_number ].max
        sequence.save!
      end
    end
end
