class NativeAttendeeVerificationJob < ApplicationJob
  self.log_arguments = false

  def perform(authorization_id, email)
    NativeAttendee::RequestPrivacy.with_private_scope { deliver(authorization_id, email) }
  end

  private
    def deliver(authorization_id, email)
      return unless NativeAttendee::Clients.enabled?

      authorization = NativeAttendeeAuthorization.find_by(id: authorization_id)
      token = authorization&.prepare_email!(email)
      return unless token && NativeAttendee::Clients.enabled?
      authorization.reload
      identity = User.find_by(id: authorization.user_id)
      return unless authorization.pending? && authorization.expires_at.future? && identity&.email == authorization.email_snapshot &&
        NativeAttendee::Clients.allowed?(authorization.client_id, authorization.callback_uri)

      NativeAttendeeMailer.verification(authorization, token).deliver_now
    end
end
