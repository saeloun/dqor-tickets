class CheckinsController < ApplicationController
  layout "checkin"
  before_action :require_checkin_operator

  EVENT_DATES = Ticket::EVENT_DATES
  MAX_BATCH_SIZE = 50
  SEARCH_LIMIT = 20

  def show
    @date = event_date(params[:date], fallback: true)
    @query = params[:q].to_s.strip
    if params[:ticket_ids].present?
      ids = selected_ids(params[:ticket_ids])
      raise ActionController::BadRequest, "Select at most #{MAX_BATCH_SIZE} tickets" if ids.size > MAX_BATCH_SIZE
      @tickets = Ticket.legacy.includes(:ticket_type, :order).where(id: ids).order(:id)
      @selection_from_admin = true
    else
      matches = search(@query).limit(SEARCH_LIMIT + 1).to_a
      @more_results = matches.size > SEARCH_LIMIT
      @tickets = matches.first(SEARCH_LIMIT)
    end
    @stats = checkin_stats(@date)
    respond_to do |format|
      format.html
      format.json do
        render json: {
          date: @date.iso8601, event_dates: EVENT_DATES.map(&:iso8601), max_batch_size: MAX_BATCH_SIZE,
          more_results: !!@more_results, stats: @stats,
          tickets: @tickets.map do |ticket|
            { id: ticket.id, attendee_name: ticket.attendee_name, attendee_email: ticket.attendee_email,
              ticket_type: ticket.ticket_type.name, order_code: ticket.order.code, order_status: ticket.order.status,
              event_starts_on: ticket.ticket_type.event_starts_on, event_ends_on: ticket.ticket_type.event_ends_on,
              canceled: ticket.canceled_at?, checked_in_at: ticket.checked_in_at[@date.iso8601] }
          end
        }
      end
    end
  rescue ArgumentError
    head :bad_request
  end

  def create
    date = event_date(params[:date])
    ticket = if params[:ticket_id].present?
      Ticket.legacy.find_by(id: params[:ticket_id])
    else
      Ticket.legacy.find_by(secret: params.expect(:secret))
    end
    source = params[:ticket_id].present? ? "manual" : "scanner"
    result = Checkins::Record.call(ticket:, date:, operator: Current.admin_user, source:)
    stats = checkin_stats(date)
    render json: result.except(:status).merge(checked_in_count: stats[:checked_in], stats:), status: result[:status]
  rescue ArgumentError
    render json: { state: "error", message: "Choose an event date" }, status: :unprocessable_content
  end

  def batch
    date = event_date(params.expect(:date))
    ids = selected_ids(params[:ticket_ids])
    unless params[:confirmed] == true && ids.any? && ids.size <= MAX_BATCH_SIZE
      return render json: { state: "error", message: "Confirm between 1 and #{MAX_BATCH_SIZE} selected tickets" }, status: :unprocessable_content
    end

    results = ids.map do |id|
      Checkins::Record.call(ticket: Ticket.legacy.find_by(id:), date:, operator: Current.admin_user, source: "batch")
        .except(:status).merge(ticket_id: id)
    end
    stats = checkin_stats(date)
    render json: { results:, checked_in_count: stats[:checked_in], stats: }
  rescue ArgumentError, ActionController::ParameterMissing
    render json: { state: "error", message: "Choose an event date and valid ticket selection" }, status: :unprocessable_content
  end

  private
    def require_authentication
      return if resume_session

      if request.format.json?
        render json: { state: "error", message: "Session expired. Sign in before checking in." }, status: :unauthorized
      else
        super
      end
    end

    def require_checkin_operator
      return if Current.admin_user&.admin? || Current.admin_user&.desk?

      render json: { state: "error", message: "Staff check-in permission required" }, status: :forbidden
    end

    def selected_ids(value)
      raise ArgumentError unless value.is_a?(Array) && value.all? { |id| id.to_s.match?(/\A[1-9]\d*\z/) }

      value.map(&:to_s).uniq
    end

    def event_date(value, fallback: false)
      date = value.present? ? Date.iso8601(value) : default_date
      raise ArgumentError unless EVENT_DATES.include?(date)

      date
    rescue ArgumentError
      raise unless fallback

      default_date
    end

    def default_date
      today = Time.use_zone("Asia/Kolkata") { Date.current }
      EVENT_DATES.include?(today) ? today : EVENT_DATES.first
    end

    def search(query)
      term = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
      Ticket.legacy.confirmed.includes(:ticket_type, :order)
        .where("lower(tickets.attendee_name) LIKE :term OR lower(tickets.attendee_email) LIKE :term OR lower(orders.email) LIKE :term OR lower(orders.code) LIKE :term", term:)
        .order(created_at: :desc)
    end

    def checkin_stats(date)
      key = date.iso8601
      valid = Ticket.legacy.confirmed.joins(:ticket_type)
        .where("ticket_types.event_starts_on IS NULL OR ticket_types.event_starts_on <= ?", date)
        .where("ticket_types.event_ends_on IS NULL OR ticket_types.event_ends_on >= ?", date)
      checked_in = valid.where("(tickets.checked_in_at ->> ?) IS NOT NULL", key)

      totals = valid.joins(:ticket_type).group("ticket_types.name").order("ticket_types.name").count
      done = checked_in.joins(:ticket_type).group("ticket_types.name").count

      {
        total: valid.count,
        checked_in: checked_in.count,
        by_type: totals.map { |name, total| { name:, total:, checked_in: done.fetch(name, 0) } }
      }
    end
end
