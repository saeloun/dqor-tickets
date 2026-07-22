class TicketAccessMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM", "tickets@deccanqueenonrails.com")

  def link(email, token)
    @url = ticket_access_url(token)
    mail(to: email, subject: "Your Deccan Queen on Rails tickets")
  end
end
