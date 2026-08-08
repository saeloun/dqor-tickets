class AccountMailer < ApplicationMailer
  def magic_link(user, token)
    @user = user
    @url = account_magic_url(token: token)
    mail(to: user.email, subject: "Your Deccan Queen on Rails sign-in link")
  end
end
