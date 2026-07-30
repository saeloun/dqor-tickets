class UserMagicLinkMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM", "tickets@deccanqueenonrails.com")

  def link(user, token)
    @user = user
    @url = user_magic_link_url(token: token)
    mail(to: user.email, subject: "Your sign-in link for Deccan Queen on Rails")
  end
end
