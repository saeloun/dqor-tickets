class ApplicationMailer < ActionMailer::Base
  self.delivery_job = MailDeliveryJob

  default from: "Deccan Queen on Rails <#{ENV.fetch("MAIL_FROM", "hello@deccanqueenonrails.com")}>"
  layout "mailer"
  helper MailerHelper
end
