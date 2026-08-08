class TicketAccessMailer < ApplicationMailer
  def link(email, token)
    @url = ticket_access_url(token: token)
    mail(to: email, subject: "Your Deccan Queen on Rails tickets")
  end
end
