require "aws-sdk-s3"

class ApplicationJob < ActiveJob::Base
  class TransientRazorpayError < StandardError; end

  DOCUMENT_ERRORS = [
    Ferrum::ProcessTimeoutError,
    Ferrum::TimeoutError,
    Ferrum::DeadBrowserError,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNRESET,
    SocketError,
    Aws::S3::Errors::ServiceError
  ].freeze
  TRANSIENT_ERRORS = [
    *DOCUMENT_ERRORS,
    Timeout::Error,
    ActiveRecord::StatementInvalid,
    Razorpay::ServerError,
    Razorpay::GatewayError,
    TransientRazorpayError
  ].freeze

  module Retryable
    extend ActiveSupport::Concern

    included do
      retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 5)
      discard_on ActiveRecord::RecordNotFound, ActiveJob::DeserializationError
    end
  end

  include Retryable
end
