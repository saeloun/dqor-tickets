class UserFromOmniauth
  class UnverifiedEmail < StandardError; end

  def self.find_or_create!(auth)
    new(auth).find_or_create!
  end

  def initialize(auth)
    @auth = auth
  end

  def find_or_create!
    Identity.find_by(provider: provider, uid: uid)&.user || find_by_verified_email || create_user!
  end

  private
    attr_reader :auth

    def provider
      auth.provider
    end

    def uid
      auth.uid.to_s
    end

    def email
      auth.info.email.to_s.strip.downcase
    end

    def verified_email?
      auth.info.verified_email.present? || auth.extra&.raw_info&.email_verified == true
    end

    def find_by_verified_email
      return nil if email.blank?
      raise UnverifiedEmail unless verified_email?

      User.find_by(email: email).tap do |user|
        user&.identities&.create!(provider: provider, uid: uid, auth: auth_payload) if user
      end
    end

    def create_user!
      raise UnverifiedEmail if email.blank?

      User.create!(
        email: email,
        name: auth.info.name.presence || auth.info.nickname.presence || "GitHub User",
        github_login: auth.info.nickname,
        timezone: "Asia/Kolkata",
        preferences: {}
      ).tap do |user|
        user.identities.create!(provider: provider, uid: uid, auth: auth_payload)
      end
    end

    def auth_payload
      {
        "provider" => auth.provider,
        "uid" => auth.uid,
        "info" => auth.info.to_h,
        "credentials" => auth.credentials.to_h
      }
    end
end
