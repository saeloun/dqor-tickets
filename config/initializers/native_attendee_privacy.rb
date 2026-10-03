require Rails.root.join("lib/native_attendee/request_privacy")
Rails.application.config.middleware.insert_before(0, NativeAttendee::RequestPrivacy)

Rails.application.config.after_initialize do
  if defined?(Sentry) && Sentry.initialized?
    NativeAttendee::RequestPrivacy.install_filters(Sentry.get_current_client.configuration)
  end
end
