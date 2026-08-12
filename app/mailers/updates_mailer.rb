class UpdatesMailer < ApplicationMailer
  def feature_digest(email)
    attachments.inline["deccan-logo.png"] = Rails.root.join("app/assets/images/deccan-logo.png").binread

    mail(to: email, subject: "New in your Deccan Queen on Rails app")
  end
end
