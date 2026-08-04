class CheckinsController < ApplicationController
  layout "checkin"

  EVENT_DATES = (8..11).map { |day| Date.new(2026, 10, day) }.freeze

  def show
    @date = event_date(params[:date], fallback: true)
    @query = params[:q].to_s.strip
    @tickets = search(@query) if @query.present?
    @stats = checkin_stats(@date)
  end

  def create
    ticket = Ticket.find_by!(secret: params.expect(:secret))
    checked_in_at = ticket.check_in!(event_date(params[:date]))
    render json: { state: "success", message: "Checked in #{ticket.attendee_name.presence || ticket.attendee_email}", checked_in_at: }
  rescue Ticket::AlreadyCheckedIn => error
    time = Time.iso8601(error.checked_in_at).in_time_zone("Asia/Kolkata").strftime("%H:%M")
    render json: { state: "warning", message: "Already checked in at #{time}" }, status: :conflict
  rescue Ticket::Canceled
    render json: { state: "error", message: "Canceled or refunded ticket" }, status: :unprocessable_content
  rescue ActiveRecord::RecordNotFound
    render json: { state: "error", message: "Ticket not found" }, status: :not_found
  rescue ArgumentError
    render json: { state: "error", message: "Choose an event date" }, status: :unprocessable_content
  end

  private
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
      Ticket.includes(:ticket_type, :order).joins(:order)
        .where("lower(tickets.attendee_name) LIKE :term OR lower(tickets.attendee_email) LIKE :term OR lower(orders.email) LIKE :term OR lower(orders.code) LIKE :term", term:)
        .order(created_at: :desc)
        .limit(20)
    end

    def checkin_stats(date)
      key = date.iso8601
      valid = Ticket.where(canceled_at: nil)
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
