class NativeAttendeeSession < ApplicationRecord
  EVENT = "dqor-2026"
  CAPABILITIES = %w[account:read passes:read].freeze
  TOKEN_FORMAT = /\Ana1_[A-Za-z0-9_-]{43}\z/
  belongs_to :user
  belongs_to :native_attendee_authorization
  attr_readonly :user_id, :native_attendee_authorization_id, :token_digest, :email_snapshot, :password_fingerprint, :client_id, :event, :expires_at
  self.filter_attributes += [ :token_digest, :email_snapshot, :password_fingerprint ]

  def self.fingerprint(user)
    Digest::SHA256.hexdigest(user.password_digest.to_s)
  end

  def self.issue!(authorization)
    token = "na1_#{SecureRandom.urlsafe_base64(32)}"
    record = create!(user_id: authorization.user_id, native_attendee_authorization: authorization,
      token_digest: Digest::SHA256.hexdigest(token), email_snapshot: authorization.email_snapshot,
      password_fingerprint: authorization.password_fingerprint, client_id: authorization.client_id,
      event: EVENT, expires_at: 30.minutes.from_now)
    [ record, token ]
  end

  def valid_identity?(identity)
    !revoked_at? && expires_at.future? && event == EVENT && identity && identity.email == email_snapshot &&
      ActiveSupport::SecurityUtils.secure_compare(password_fingerprint, self.class.fingerprint(identity)) &&
      NativeAttendee::Clients.mapping.key?(client_id)
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked_at?
  end
end
