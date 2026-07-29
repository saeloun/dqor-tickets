class Users::MagicLinksController < ApplicationController
  allow_unauthenticated_access only: %i[new create show]

  TOKEN_PURPOSE = :user_magic_link
  TOKEN_EXPIRY = 15.minutes

  rate_limit to: 5, within: 5.minutes, only: :create, name: "ip", with: -> { redirect_to login_path, notice: sent_notice }
  rate_limit to: 3, within: 1.hour, only: :create, name: "email", by: -> { params[:email].to_s.strip.downcase }, with: -> { redirect_to login_path, notice: sent_notice }

  def new
  end

  def create
    email = params[:email].to_s.strip.downcase
    user = User.find_by(email: email) if email.present?

    if user
      UserMagicLinkMailer.link(user, generate_token(user)).deliver_later
    end

    redirect_to login_path, notice: sent_notice
  end

  def show
    user_id = verifier.verified(params[:token].to_s, purpose: TOKEN_PURPOSE)
    user = User.find_by(id: user_id)

    if user.nil?
      return redirect_to login_path, alert: "That link is invalid or has expired. Request a new one."
    end

    start_new_session_for(user)
    redirect_to after_authentication_url
  end

  private
    def sent_notice
      "If that email has an account, we have sent a sign-in link. Check your inbox."
    end

    def generate_token(user)
      verifier.generate(user.id, purpose: TOKEN_PURPOSE, expires_in: TOKEN_EXPIRY)
    end

    def verifier
      @verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key("user_magic_link"),
        digest: "SHA256",
        serializer: JSON,
        url_safe: true
      )
    end
end
