class NativeAttendeeMailer < ApplicationMailer
  self.delivery_job = NativeAttendeeMailDeliveryJob
  self.logger = nil

  class << self
    private
      def set_payload_for_mail(payload, mail)
        super
        payload[:mail] = "[FILTERED native verification email]"
        payload[:to] = [ "[FILTERED]" ]
        payload[:cc] = [ "[FILTERED]" ] if payload.key?(:cc)
        payload[:bcc] = [ "[FILTERED]" ] if payload.key?(:bcc)
      end
  end

  def verification(authorization, token)
    @url = native_attendee_verify_url(token: token, host: NativeAttendee::Clients::HOST, protocol: "https")
    @app_name = NativeAttendee::Clients.name(authorization.client_id)
    mail(to: authorization.email_snapshot, subject: "Verify your DQOR native account read request")
  end
end
