class OrderMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM", "tickets@deccanqueenonrails.com")

  def confirmation(order, documents_pending: false)
    @order = order
    @documents_pending = documents_pending
    unless @documents_pending
      attach(@order.invoices.invoice.sole)
      @order.tickets.find_each { |ticket| attach(ticket) }
    end
    mail(to: @order.email, subject: "Your Deccan Queen on Rails tickets")
  end

  def refund_note(refund)
    @refund = refund
    @order = refund.order
    @credit_note = @order.invoices.credit_note.find_by!(number: refund.credit_note_number)
    attach(@credit_note)
    mail(to: @order.email, subject: "Your Deccan Queen on Rails credit note")
  end

  private
    def attach(record)
      attachments[record.pdf.filename.to_s] = record.pdf.download
    end
end
