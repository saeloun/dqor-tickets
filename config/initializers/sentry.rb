if ENV["SENTRY_DSN"].present?
  Rails.application.config.filter_parameters += [ :buyer, :gst, :billing_state_code, :razorpay_signature ]
  parameter_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
    config.enabled_environments = [ "production" ]
    config.environment = Rails.env
    config.release = ENV["GIT_SHA"] if ENV["GIT_SHA"].present?
    config.traces_sample_rate = 0.2
    config.send_default_pii = false
    config.before_send = lambda do |event, _hint|
      event.request.data = parameter_filter.filter(event.request.data) if event.request&.data.is_a?(Hash)
      event
    end
  end
end
