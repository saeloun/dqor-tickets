class Api::Public::V1::EventsController < ActionController::API
  before_action :require_public_events
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError, ActiveRecord::StatementInvalid, with: :unavailable

  def index
    render_snapshot PublicEvents::Snapshot.index(params[:page])
  end

  def show
    raise ActiveRecord::RecordNotFound unless params[:id].to_s.match?(/\Ahosted-event-[1-9][0-9]{0,18}\z/)

    id = params[:id].delete_prefix("hosted-event-").to_i
    raise ActiveRecord::RecordNotFound if id > 9_223_372_036_854_775_807

    event = Event.published.includes(:organization).find(id)
    render_snapshot PublicEvents::Snapshot.show(event)
  end

  private
    def require_public_events
      not_found unless Rails.configuration.x.organizer_platform_enabled && Rails.configuration.x.public_events_enabled
    end

    def render_snapshot(payload)
      response.headers["Cache-Control"] = "public, max-age=0, must-revalidate"
      render json: payload if stale?(etag: payload.fetch(:content_version), public: true)
    end

    def not_found
      render_error("event_not_found", "Published event not found.", :not_found)
    end

    def unavailable
      render_error("events_unavailable", "Events temporarily unavailable. Try again later.", :service_unavailable)
    end

    def render_error(code, message, status)
      response.headers["Cache-Control"] = "no-store"
      response.headers.delete("ETag")
      render json: { schema_version: 1, error: { code: code, message: message } }, status: status
    end
end
