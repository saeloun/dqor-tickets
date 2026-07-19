class MailDeliveryJob < ActionMailer::MailDeliveryJob
  include ApplicationJob::Retryable
end
