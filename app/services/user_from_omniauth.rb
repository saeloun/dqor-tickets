class UserFromOmniauth
  class UnverifiedEmail < StandardError; end

  def self.find_or_create!(auth)
    new(auth).find_or_create!
  end

  def initialize(auth)
    @auth = auth
  end

  def find_or_create!
    identity = Identity.find_by(provider: auth.provider, uid: auth.uid.to_s)
    return identity.user if identity

    email = auth.info.email.to_s.strip.downcase
    verified = auth.dig(:extra, :raw_info, :email_verified)

    raise UnverifiedEmail if email.blank? || !verified

    user = User.find_by(email: email) || User.new(email: email)
    user.name ||= auth.info.name
    user.github_login ||= auth.info.nickname
    user.save!

    user.identities.create!(provider: auth.provider, uid: auth.uid.to_s, auth: auth.as_json)

    user
  end

  private
    attr_reader :auth
end
