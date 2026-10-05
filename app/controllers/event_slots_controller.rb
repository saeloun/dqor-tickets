class EventSlotsController < ApplicationController
  around_action :slot_time_zone
  before_action :require_operator
  before_action :require_organizer, only: %i[new create edit update correct]

  def index
    @slots = EventSlot.order(:starts_at)
  end

  def show
    @slot = EventSlot.find(params[:id])
    @query = params[:q].to_s.strip
    @tickets = if @query.length >= 2
      term = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
      Ticket.legacy.confirmed.includes(:ticket_type)
        .where("lower(tickets.attendee_name) LIKE :term OR lower(tickets.attendee_email) LIKE :term", term:).order(:id).limit(20)
    else
      []
    end
    response.headers["Cache-Control"] = "no-store"
  end

  def new
    @slot = EventSlot.new
  end

  def create
    @slot = EventSlot.new(slot_params)
    if @slot.save
      redirect_to event_slots_path
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @slot = EventSlot.find(params[:id])
  end

  def update
    @slot = EventSlot.find(params[:id])
    @slot.with_lock do
      if @slot.update(slot_params)
        redirect_to event_slots_path
      else
        render :edit, status: :unprocessable_content
      end
    end
  end

  def redeem
    slot = EventSlot.find(params[:id])
    ticket = params[:ticket_id].present? ? Ticket.legacy.find_by(id: params[:ticket_id]) : Ticket.legacy.find_by(secret: params[:secret])
    redemption = EventSlots::Redeem.call(slot:, ticket:, operator: Current.admin_user, request_key: params[:request_key])
    render json: { state: "success", message: "#{slot.name}: redeemed at #{redemption.redeemed_at.iso8601}", redeemed_at: redemption.redeemed_at, redemption_id: redemption.id }
  rescue EventSlots::Redeem::Rejected => error
    render json: { state: "error", message: error.message }, status: :unprocessable_content
  end

  def correct
    redemption = EventSlot.find(params[:id]).redemptions.find(params[:redemption_id])
    EventSlots::Redeem.correct!(redemption:, operator: Current.admin_user, reason: params[:reason])
    redirect_to event_slot_path(redemption.event_slot)
  rescue EventSlots::Redeem::Rejected => error
    render plain: error.message, status: :unprocessable_content
  end

  private
    def require_operator
      head :forbidden unless Current.admin_user&.admin? || Current.admin_user&.desk?
    end

    def require_organizer
      head :forbidden unless Current.admin_user&.admin?
    end

    def slot_time_zone(&block)
      Time.use_zone("Asia/Kolkata", &block)
    end

    def slot_params
      values = params.require(:event_slot).permit(:name, :starts_at, :ends_at, :active, :capacity, :redemption_limit, ticket_type_ids: [])
      values[:ticket_type_ids] = Array(values[:ticket_type_ids]).reject(&:blank?)
      values
    end
end
