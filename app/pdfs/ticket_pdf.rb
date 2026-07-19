require "prawn/qrcode"

class TicketPdf
  def initialize(ticket)
    @ticket = ticket
  end

  def render
    Prawn::Document.new(page_size: [ 420, 595 ], margin: 40).tap do |pdf|
      pdf.fill_color "9B1C31"
      pdf.text "DECCAN QUEEN ON RAILS", size: 20, style: :bold, align: :center
      pdf.fill_color "000000"
      pdf.text "Pune 2026", size: 12, align: :center
      pdf.move_down 28
      pdf.text attendee_name, size: 18, style: :bold, align: :center
      pdf.text ticket.ticket_type.name, size: 14, align: :center
      pdf.text validity, size: 11, align: :center
      pdf.move_down 24
      pdf.print_qr_code ticket.secret, extent: 160, pos: [ 90, pdf.cursor ]
      pdf.move_down 180
      pdf.text "Order #{ticket.order.code}", size: 10, align: :center
      pdf.text ticket.secret, size: 8, align: :center
    end.render
  end

  private
    attr_reader :ticket

    def attendee_name
      ticket.attendee_name.presence || ticket.order.buyer_name
    end

    def validity
      case ticket.ticket_type.slug
      when "explore-pune-day"
        "Valid October 11, 2026"
      when /rails-girls/
        "Valid October 10, 2026"
      else
        "Valid October 8-9, 2026"
      end
    end
end
