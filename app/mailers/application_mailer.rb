class ApplicationMailer < ActionMailer::Base
  self.delivery_job = MailDeliveryJob

  default from: "from@example.com"
  layout "mailer"
  helper MailerHelper
end
