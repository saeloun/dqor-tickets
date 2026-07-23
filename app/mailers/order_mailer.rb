class OrderMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM", "tickets@deccanqueenonrails.com")

  def confirmation(order, documents_pending: false)
    @order = order
    invoice = @order.invoices.invoice.first unless documents_pending
    @documents_pending = documents_pending || !invoice&.pdf&.attached?

    attach(invoice) unless @documents_pending
    mail(to: @order.email, subject: "Your Deccan Queen on Rails tickets")
  end

  def order_link(order)
    @order = order
    mail(to: @order.email, subject: "Your Deccan Queen on Rails order link")
  end

  def ticket(ticket)
    @ticket = ticket
    @order = ticket.order
    attach(@ticket)
    mail(to: @ticket.attendee_email, subject: "Your Deccan Queen on Rails ticket")
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
