require "zip"

class PkpassGenerator
  WWDR_PATH = Rails.root.join("config/certs/AppleWWDRCAG4.pem")

  def self.configured?
    cert_pem.present? && key_pem.present? &&
      ENV["APPLE_PASS_TYPE_ID"].present? && ENV["APPLE_TEAM_ID"].present?
  end

  def self.cert_pem
    decode(ENV["APPLE_PASS_CERT"])
  end

  def self.key_pem
    decode(ENV["APPLE_PASS_KEY"])
  end

  def self.decode(value)
    return nil if value.blank?

    value.include?("BEGIN") ? value : Base64.decode64(value)
  end

  def initialize(ticket)
    @ticket = ticket
  end

  def generate
    files = images.merge("pass.json" => pass_json)
    files["manifest.json"] = manifest(files)
    files["signature"] = signature(files["manifest.json"])
    zip(files)
  end

  private
    attr_reader :ticket

    def pass_json
      {
        formatVersion: 1,
        passTypeIdentifier: ENV["APPLE_PASS_TYPE_ID"],
        teamIdentifier: ENV["APPLE_TEAM_ID"],
        organizationName: "Deccan Queen on Rails",
        description: "Deccan Queen on Rails ticket",
        serialNumber: ticket.secret,
        logoText: "Deccan Queen on Rails",
        foregroundColor: "rgb(255, 248, 236)",
        backgroundColor: "rgb(122, 18, 32)",
        labelColor: "rgb(232, 205, 165)",
        barcodes: [ { format: "PKBarcodeFormatQR", message: ticket.secret, messageEncoding: "iso-8859-1", altText: ticket.secret } ],
        eventTicket: {
          primaryFields: [ { key: "event", label: "EVENT", value: "Deccan Queen on Rails" } ],
          secondaryFields: [
            { key: "name", label: "ATTENDEE", value: ticket.attendee_name.to_s },
            { key: "type", label: "PASS", value: ticket.ticket_type.name }
          ],
          auxiliaryFields: [
            { key: "when", label: "WHEN", value: "Oct 8–11, 2026" },
            { key: "where", label: "WHERE", value: "Hyatt Regency, Pune" }
          ],
          backFields: [
            { key: "order", label: "Order", value: ticket.order.code },
            { key: "help", label: "At the venue", value: "Show this pass at the registration desk to check in." }
          ]
        }
      }.to_json
    end

    def images
      icon = Rails.root.join("public/icon.png").binread
      { "icon.png" => icon, "icon@2x.png" => icon, "logo.png" => icon, "logo@2x.png" => icon }
    end

    def manifest(files)
      files.transform_values { |content| Digest::SHA1.hexdigest(content) }.to_json
    end

    def signature(manifest_json)
      cert = OpenSSL::X509::Certificate.new(self.class.cert_pem)
      key = OpenSSL::PKey::RSA.new(self.class.key_pem, ENV["APPLE_PASS_KEY_PASSWORD"].to_s)
      wwdr = OpenSSL::X509::Certificate.new(File.read(WWDR_PATH))
      flags = OpenSSL::PKCS7::BINARY | OpenSSL::PKCS7::DETACHED
      OpenSSL::PKCS7.sign(cert, key, manifest_json, [ wwdr ], flags).to_der
    end

    def zip(files)
      Zip::OutputStream.write_buffer do |zos|
        files.each do |name, content|
          zos.put_next_entry(name)
          zos.write(content)
        end
      end.string
    end
end
