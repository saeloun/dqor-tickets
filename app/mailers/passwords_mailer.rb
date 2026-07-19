class PasswordsMailer < ApplicationMailer
  def reset(admin_user)
    @admin_user = admin_user
    mail subject: "Reset your password", to: admin_user.email
  end
end
