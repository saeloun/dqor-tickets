require "digest"

class ChatLoginGrant < ApplicationRecord
  STATE_FORMAT = /\A[a-zA-Z0-9]{32}\z/
  CODE_FORMAT = /\A[a-zA-Z0-9_-]{43}\z/

  def self.issue!(email:, name:, state:)
    code = SecureRandom.urlsafe_base64(32)
    create!(email:, name:, state:, code_digest: Digest::SHA256.hexdigest(code), expires_at: 60.seconds.from_now)
    code
  end

  def self.redeem(code:, state:)
    return unless CODE_FORMAT.match?(code.to_s) && STATE_FORMAT.match?(state.to_s)

    transaction do
      grant = lock.find_by(code_digest: Digest::SHA256.hexdigest(code))
      if grant && grant.expires_at.future? && ActiveSupport::SecurityUtils.secure_compare(grant.state, state)
        payload = { verified: true, email: grant.email, name: grant.name }
        grant.destroy!
        payload
      end
    end
  end
end
