require "csv"

class Organizer::OperationsController < Organizer::BaseController
  prepend_before_action :require_operations
  before_action :require_commercial_member
  before_action :set_operations_event
  before_action :private_response

  RECORDS = {
    "contacts" => [ Operations::BusinessContact, %i[name email outreach_approved] ],
    "deals" => [ Operations::SponsorDeal, %i[title business_contact_id amount_paise stage contribution] ],
    "vendors" => [ Operations::VendorEngagement, %i[title business_contact_id amount_paise] ],
    "tasks" => [ Operations::FulfillmentTask, %i[title sponsor_deal_id due_on] ],
    "entries" => [ Operations::ManualEntry, %i[sponsor_deal_id vendor_engagement_id kind amount_paise occurred_on reference] ]
  }.freeze

  def index
    load_dashboard
    respond_to do |format|
      format.html
      format.csv do
        # Deliberately excludes contact details and free-text reference/notes.
        data = CSV.generate do |csv|
          csv << %w[id kind amount_paise occurred_on sponsor_deal_id vendor_engagement_id]
          @entries.each { |e| csv << [ e.id, e.kind, e.amount_paise, e.occurred_on, e.sponsor_deal_id, e.vendor_engagement_id ] }
        end
        send_data data, filename: "event-#{@event.id}-manual-cash.csv", type: "text/csv"
      end
    end
  end

  def create
    klass, fields = RECORDS.fetch(params[:kind]) { raise ActiveRecord::RecordNotFound }
    attributes = params.require(:record).permit(*fields)
    { business_contact_id: Operations::BusinessContact, sponsor_deal_id: Operations::SponsorDeal, vendor_engagement_id: Operations::VendorEngagement }.each do |key, target|
      scoped(target).find(attributes[key]) if attributes[key].present?
    end
    @record = scoped(klass).new(attributes)
    saved = if @record.is_a?(Operations::ManualEntry)
      Operations::RecordEntry.call(@record, user: current_user)
    else
      klass.transaction do
        if @record.save
          audit!(@record, "create")
          true
        else
          false
        end
      end
    end
    if saved
      redirect_to organizer_organization_event_operations_path(@organization, @event), notice: "Record saved."
    else
      load_dashboard
      render :index, status: :unprocessable_content
    end
  end

  def commit_deal
    deal = scoped(Operations::SponsorDeal).find(params[:id])
    deal.with_lock do
      if deal.stage == "pledged"
        deal.update!(stage: "committed")
        audit!(deal, "commit")
      end
    end
    redirect_to organizer_organization_event_operations_path(@organization, @event), notice: "Sponsor commitment recorded."
  end

  def complete
    task = scoped(Operations::FulfillmentTask).find(params[:id])
    task.with_lock do
      unless task.completed?
        task.update!(completed: true)
        audit!(task, "complete")
      end
    end
    redirect_to organizer_organization_event_operations_path(@organization, @event), notice: "Deliverable completed."
  end

  def draft
    @contact = scoped(Operations::BusinessContact).find(params[:id])
    head :unprocessable_content unless @contact.outreach_approved?
  end

  private
    def require_operations
      head :not_found unless Rails.configuration.x.organizer_operations_enabled
    end

    def require_commercial_member
      head :forbidden unless @membership.owner? || @membership.admin?
    end

    def set_operations_event
      @event = @organization.events.find(params[:event_id])
    end

    def private_response
      response.headers["Cache-Control"] = "no-store"
    end

    def scoped(klass)
      klass.where(event: @event)
    end

    def audit!(record, action)
      Operations::AuditLog.create!(event: @event, user: current_user, action: action, record_kind: record.class.model_name.element, record_id: record.id)
    end

    def load_dashboard
      @contacts = scoped(Operations::BusinessContact).order(:name)
      @deals = scoped(Operations::SponsorDeal).order(:id)
      @vendors = scoped(Operations::VendorEngagement).order(:id)
      @tasks = scoped(Operations::FulfillmentTask).order(:id)
      @entries = scoped(Operations::ManualEntry).order(:id)
    end
end
