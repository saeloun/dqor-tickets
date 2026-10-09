module ConferenceBadges
  class Selection
    MAX_BADGES = 50
    class Invalid < StandardError; end
    Badge = Data.define(:ticket_id, :name, :company, :qr_svg, :duplicate, :sample)

    def self.duplicate_ids
      identities = Hash.new { |hash, key| hash[key] = [] }
      ConferenceInventory.confirmed.pluck(:id, :attendee_name, :attendee_email).each do |id, name, email|
        [ [ :name, name ], [ :email, email ] ].each do |kind, value|
          normalized = value.to_s.unicode_normalize(:nfkc).strip.downcase.gsub(/\s+/, " ")
          identities[[ kind, normalized ]] << id if normalized.present?
        end
      end
      identities.values.select { |ids| ids.length > 1 }.flatten.uniq
    end

    def self.build(ids:, companies:, confirmed:)
      unless [ true, "true" ].include?(confirmed) && ids.is_a?(Array) && ids.length.between?(1, MAX_BADGES) && ids.all? { |id| id.to_s.match?(/\A[1-9]\d{0,18}\z/) }
        raise Invalid, "Confirm between 1 and #{MAX_BADGES} selected passes."
      end
      ids = ids.map(&:to_i)
      raise Invalid, "Select each pass only once." unless ids.uniq.length == ids.length
      unless companies.is_a?(Hash) && companies.keys.all? { |id| ids.include?(id.to_s.to_i) && id.to_s.match?(/\A[1-9]\d{0,18}\z/) }
        raise Invalid, "Company text must belong to selected passes."
      end
      companies.each_value do |value|
        unless value.is_a?(String) && value.length <= 80 && !value.match?(/[[:cntrl:]]/)
          raise Invalid, "Company text must be at most 80 characters without control characters."
        end
      end
      tickets = ConferenceInventory.confirmed.where(id: ids).to_a
      raise Invalid, "A selected pass is no longer a confirmed conference pass. Review your selection." unless tickets.length == ids.length
      duplicates = duplicate_ids
      tickets.sort_by { |ticket| [ ticket.attendee_name.to_s.unicode_normalize(:nfkc).strip.downcase, ticket.id ] }.map do |ticket|
        name = ticket.attendee_name.to_s.strip
        raise Invalid, "Pass #{ticket.id} needs an attendee name before printing." if name.blank?
        raise Invalid, "Pass #{ticket.id} needs a name of at most 120 characters for the badge." if name.length > 120
        Badge.new(ticket_id: ticket.id, name:, company: companies.fetch(ticket.id.to_s, "").strip,
          qr_svg: Document.qr_svg(ticket.secret), duplicate: duplicates.include?(ticket.id), sample: false)
      end
    end

    def self.sample
      [ "Sample Ada", "Sample Grace", "Sample Attendee With A Longer Name", "Sample Attendee" ].map do |name|
        Badge.new(ticket_id: nil, name:, company: "Sample company", qr_svg: Document.qr_svg(ScannerRehearsalsController::TEST_QR), duplicate: false, sample: true)
      end
    end
  end
end
