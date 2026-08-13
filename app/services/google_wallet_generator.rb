class GoogleWalletGenerator
  SAVE_URL = "https://pay.google.com/gp/v/save/".freeze

  def self.configured?
    issuer_id.present? && service_account_email.present? && private_key_pem.present?
  end

  def self.issuer_id
    ENV["GOOGLE_WALLET_ISSUER_ID"].presence
  end

  def self.service_account_email
    ENV["GOOGLE_WALLET_SA_EMAIL"].presence
  end

  def self.private_key_pem
    value = ENV["GOOGLE_WALLET_SA_KEY"]
    return nil if value.blank?

    value.include?("BEGIN") ? value : Base64.decode64(value)
  end

  def initialize(ticket)
    @ticket = ticket
  end

  def save_url
    SAVE_URL + jwt
  end

  private
    attr_reader :ticket

    def jwt
      key = OpenSSL::PKey::RSA.new(self.class.private_key_pem)
      claims = {
        iss: self.class.service_account_email,
        aud: "google",
        typ: "savetowallet",
        iat: Time.now.to_i,
        payload: {
          eventTicketClasses: [ event_ticket_class ],
          eventTicketObjects: [ event_ticket_object ]
        }
      }
      JWT.encode(claims, key, "RS256")
    end

    def class_id
      "#{self.class.issuer_id}.dqor_event"
    end

    def ticket_object_id
      "#{self.class.issuer_id}.#{ticket.secret}"
    end

    def event_ticket_class
      {
        id: class_id,
        issuerName: "Deccan Queen on Rails",
        reviewStatus: "UNDER_REVIEW",
        eventName: { defaultValue: { language: "en-US", value: "Deccan Queen on Rails" } },
        venue: {
          name: { defaultValue: { language: "en-US", value: "Hyatt Regency Pune" } },
          address: { defaultValue: { language: "en-US", value: "Hyatt Regency, Pune, Maharashtra, India" } }
        },
        dateTime: { start: "2026-10-08T09:00:00+05:30", end: "2026-10-11T18:00:00+05:30" },
        logo: { sourceUri: { uri: "https://deccanqueenonrails.com/icon.png" } },
        hexBackgroundColor: "#7a1220"
      }
    end

    def event_ticket_object
      {
        id: ticket_object_id,
        classId: class_id,
        state: "ACTIVE",
        ticketHolderName: ticket.attendee_name.to_s,
        ticketType: { defaultValue: { language: "en-US", value: ticket.ticket_type.name } },
        barcode: { type: "QR_CODE", value: ticket.secret, alternateText: ticket.secret }
      }
    end
end
