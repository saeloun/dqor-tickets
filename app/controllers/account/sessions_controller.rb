class Account::SessionsController < ApplicationController
  allow_unauthenticated_access

  MAGIC_PURPOSE = :account_magic_link
  MAGIC_EXPIRY = 30.minutes
  SENT_NOTICE = "Check your email for a sign-in link.".freeze

  rate_limit to: 5, within: 5.minutes, only: :create, with: -> { redirect_to account_sign_in_path, notice: SENT_NOTICE }

  def new
  end

  def create
    email = params[:email].to_s.strip.downcase

    if email.match?(URI::MailTo::EMAIL_REGEXP)
      user = User.find_or_create_by!(email: email)
      AccountMailer.magic_link(user, magic_token(user)).deliver_later
    end

    redirect_to account_sign_in_path, notice: SENT_NOTICE
  end

  def magic
    user_id = verifier.verified(params[:token].to_s, purpose: MAGIC_PURPOSE)
    user = User.find_by(id: user_id) if user_id

    if user
      sign_in(user)
      redirect_to account_root_path, notice: "You’re signed in."
    else
      redirect_to account_sign_in_path, alert: "That link is invalid or has expired. Request a new one."
    end
  end

  def destroy
    sign_out_user
    redirect_to root_path, notice: "Signed out."
  end

  private
    def magic_token(user)
      verifier.generate(user.id, purpose: MAGIC_PURPOSE, expires_in: MAGIC_EXPIRY)
    end

    def verifier
      Rails.application.message_verifier(MAGIC_PURPOSE)
    end
end
