class NativeAttendeeAuthorization < ApplicationRecord
  class Invalid < StandardError; end
  STATE_FORMAT = /\A[A-Za-z0-9_-]{32,128}\z/
  CHALLENGE_FORMAT = /\A[A-Za-z0-9_-]{43}\z/
  VERIFIER_FORMAT = /\A[A-Za-z0-9._~-]{43,128}\z/
  CODE_FORMAT = /\Anac1_[A-Za-z0-9_-]{43}\z/
  PURPOSE = :native_attendee_verification
  belongs_to :user, optional: true
  has_one :native_attendee_session
  enum :status, { pending: 0, verified: 1, issued: 2, consumed: 3, canceled: 4, expired: 5 }
  attr_readonly :client_id, :callback_uri, :code_challenge, :state, :creation_digest, :expires_at
  self.filter_attributes += [ :callback_uri, :state, :code_challenge, :creation_digest, :email_request_digest, :email_snapshot, :verification_nonce_digest, :password_fingerprint, :consent_digest, :code_digest ]
  validate :immutable_bindings
  validate :terminal_lifecycle

  def self.start!(client_id:, callback_uri:, state:, code_challenge:, method:)
    raise Invalid unless NativeAttendee::Clients.allowed?(client_id, callback_uri) && method == "S256" &&
      state.is_a?(String) && STATE_FORMAT.match?(state) && code_challenge.is_a?(String) && CHALLENGE_FORMAT.match?(code_challenge)

    creation = SecureRandom.urlsafe_base64(32)
    record = create!(client_id: client_id, callback_uri: callback_uri, state: state, code_challenge: code_challenge,
      creation_digest: digest(creation), expires_at: 10.minutes.from_now)
    [ record, creation ]
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(value)
  end

  def self.challenge(verifier)
    Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end

  def self.exchange(code:, code_verifier:, client_id:, callback_uri:)
    return unless code.is_a?(String) && CODE_FORMAT.match?(code) && code_verifier.is_a?(String) && VERIFIER_FORMAT.match?(code_verifier)

    record = find_by(code_digest: digest(code))
    return unless record

    record.with_identity_lock do |identity|
      next unless record.active? && record.issued? && record.code_expires_at.future? &&
        record.client_id == client_id && record.callback_uri == callback_uri && NativeAttendee::Clients.allowed?(client_id, callback_uri) &&
        ActiveSupport::SecurityUtils.secure_compare(record.code_challenge, challenge(code_verifier))

      unless record.identity_matches?(identity)
        record.update!(status: :canceled, canceled_at: Time.current)
        next
      end
      record.update!(status: :consumed, consumed_at: Time.current)
      NativeAttendeeSession.issue!(record)
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def active?
    return false if consumed? || canceled? || expired?
    if expires_at <= Time.current || (issued? && code_expires_at <= Time.current)
      update!(status: :expired)
      return false
    end
    NativeAttendee::Clients.allowed?(client_id, callback_uri)
  end

  def accepts_creation?(proof)
    proof.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(creation_digest, self.class.digest(proof))
  end

  def request_email!(email, proof:)
    result = with_lock do
      next :invalid unless active? && pending? && accepts_creation?(proof)
      next :duplicate if email_request_digest?

      update!(email_request_digest: self.class.digest(email))
      :accepted
    end
    raise Invalid if result == :invalid

    result == :accepted
  end

  def prepare_email!(email)
    User.transaction do
      identity = User.lock.find_by(email: email)
      with_lock do
        next unless active? && pending? && !verification_nonce_digest? && email_request_digest == self.class.digest(email) && identity

        nonce = SecureRandom.urlsafe_base64(32)
        update!(user: identity, email_snapshot: identity.email, verification_nonce_digest: self.class.digest(nonce))
        self.class.verifier.generate({ "id" => id, "user_id" => identity.id, "email" => email_snapshot, "client_id" => client_id, "nonce" => nonce }, purpose: PURPOSE, expires_at: expires_at)
      end
    end
  end

  def with_identity_lock
    User.transaction do
      identity = User.lock.find_by(id: user_id)
      with_lock { yield identity }
    end
  end

  def verify!(payload)
    result = with_identity_lock do |identity|
      next unless active? && pending? && verification_nonce_digest? && payload["user_id"] == user_id &&
        payload["email"] == email_snapshot && payload["client_id"] == client_id && payload["nonce"].is_a?(String) &&
        ActiveSupport::SecurityUtils.secure_compare(verification_nonce_digest, self.class.digest(payload["nonce"]))

      unless identity && identity.email == email_snapshot
        update!(status: :canceled, canceled_at: Time.current)
        next
      end
      consent = SecureRandom.urlsafe_base64(32)
      update!(status: :verified, verified_at: Time.current, password_fingerprint: NativeAttendeeSession.fingerprint(identity), consent_digest: self.class.digest(consent))
      consent
    end
    raise Invalid unless result

    result
  end

  def identity_matches?(identity)
    identity && identity.email == email_snapshot && password_fingerprint? &&
      ActiveSupport::SecurityUtils.secure_compare(password_fingerprint, NativeAttendeeSession.fingerprint(identity))
  end

  def accepts_consent?(proof)
    proof.is_a?(String) && consent_digest? && ActiveSupport::SecurityUtils.secure_compare(consent_digest, self.class.digest(proof))
  end

  def verified_context?(proof)
    with_identity_lock do |identity|
      next false unless active? && verified? && accepts_consent?(proof)
      unless identity_matches?(identity)
        update!(status: :canceled, canceled_at: Time.current)
        next false
      end
      true
    end
  end

  def issue_code!(proof:)
    result = with_identity_lock do |identity|
      next unless active? && verified? && accepts_consent?(proof)
      unless identity_matches?(identity)
        update!(status: :canceled, canceled_at: Time.current)
        next
      end
      code = "nac1_#{SecureRandom.urlsafe_base64(32)}"
      update!(status: :issued, code_digest: self.class.digest(code), code_expires_at: [ 60.seconds.from_now, expires_at ].min)
      code
    end
    raise Invalid unless result

    result
  end

  def cancel!(proof:)
    result = with_lock do
      next false unless active? && (pending? ? accepts_creation?(proof) : accepts_consent?(proof))

      update!(status: :canceled, canceled_at: Time.current)
    end
    raise Invalid unless result

    result
  end

  private
    def immutable_bindings
      return if new_record?

      %w[user_id email_request_digest email_snapshot verification_nonce_digest password_fingerprint consent_digest code_digest code_expires_at verified_at].each do |attribute|
        errors.add(attribute, "cannot change") if will_save_change_to_attribute?(attribute) && attribute_in_database(attribute).present?
      end
    end

    def terminal_lifecycle
      return if new_record? || !will_save_change_to_status?

      allowed = { "pending" => %w[verified canceled expired], "verified" => %w[issued canceled expired], "issued" => %w[consumed canceled expired] }
      errors.add(:status, "cannot transition") unless allowed.fetch(status_in_database, []).include?(status)
    end
end
