class InvoicePdf
  SAC = "998596"

  def initialize(invoice)
    @invoice = invoice
  end

  def render
    Prawn::Document.new(page_size: "A4", margin: 42).tap do |pdf|
      heading(pdf)
      parties(pdf)
      lines(pdf)
      totals(pdf)
      pdf.number_pages "Page <page> of <total>", at: [ 0, 0 ], align: :right, size: 8
    end.render
  end

  private
    attr_reader :invoice

    def heading(pdf)
      pdf.fill_color "9B1C31"
      pdf.text invoice.credit_note? ? "CREDIT NOTE" : "GST TAX INVOICE", size: 22, style: :bold
      pdf.fill_color "000000"
      pdf.text invoice.number, size: 12
      pdf.text "Issued on #{invoice.issued_on.to_fs(:long)}", size: 9
      pdf.move_down 16
      pdf.stroke_horizontal_rule
      pdf.move_down 14
    end

    def parties(pdf)
      pdf.text "Supplier", style: :bold
      pdf.text ENV.fetch("SELLER_NAME", "Saeloun")
      pdf.text ENV.fetch("SELLER_ADDRESS", "")
      pdf.text "GSTIN: #{ENV.fetch('SELLER_GSTIN', '')}"
      pdf.move_down 12
      pdf.text "Buyer", style: :bold
      pdf.text invoice.buyer_snapshot.fetch("gst_legal_name").presence || invoice.buyer_snapshot.fetch("buyer_name")
      pdf.text invoice.buyer_snapshot.fetch("email")
      pdf.text "GSTIN: #{invoice.buyer_snapshot['gstin'].presence || 'B2C'}"
      pdf.text "Place of supply: #{invoice.buyer_snapshot['billing_state_code'].presence || '27'}"
      pdf.move_down 16
    end

    def lines(pdf)
      invoice.line_items.each_with_index do |line_item, index|
        pdf.text "#{index + 1}. #{line_item.fetch('name')}", style: :bold
        pdf.text "SAC #{SAC} | Gross #{money(line_item.fetch('price_paise'))} | Discount #{money(line_item.fetch('discount_paise'))}"
        pdf.text "Taxable #{money(line_item.fetch('taxable'))} | CGST #{money(line_item.fetch('cgst'))} | SGST #{money(line_item.fetch('sgst'))} | IGST #{money(line_item.fetch('igst'))} | Total #{money(line_item.fetch('total_paise'))}"
        pdf.move_down 10
      end
      pdf.stroke_horizontal_rule
      pdf.move_down 12
    end

    def totals(pdf)
      totals = invoice.line_items.each_with_object(Hash.new(0)) do |line_item, sum|
        %w[taxable cgst sgst igst total_paise].each { |key| sum[key] += line_item.fetch(key) }
      end
      pdf.text "Taxable total: #{money(totals['taxable'])}", align: :right
      pdf.text "CGST: #{money(totals['cgst'])}  SGST: #{money(totals['sgst'])}  IGST: #{money(totals['igst'])}", align: :right
      pdf.text "Grand total: #{money(totals['total_paise'])}", align: :right, size: 13, style: :bold
    end

    def money(paise)
      "INR #{format('%.2f', paise / 100.0)}"
    end
end
