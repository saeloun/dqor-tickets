class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern, unless: -> { turbo_native_app? }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :turbo_native_app?

  private
    def turbo_native_app?
      request.user_agent.to_s.match?(/Turbo Native|Hotwire Native/)
    end
end
