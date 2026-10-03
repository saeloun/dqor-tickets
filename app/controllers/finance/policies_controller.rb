class Finance::PoliciesController < Finance::BaseController
  before_action :load_policy, only: %i[show update configure approve duplicate reopen]
  rescue_from ActiveRecord::StaleObjectError, with: -> { render plain: "This review changed. Reload before editing or approving.", status: :conflict }
  rescue_from ActiveRecord::ReadOnlyRecord, with: -> { render plain: "Approved reviews cannot be edited. Start a new draft.", status: :conflict }

  def index
    @policies = InvoicePolicyReview.includes(:created_by, :approved_by).order(created_at: :desc).limit(100)
  end

  def new
    @policy = InvoicePolicyReview.new
    render :show
  end

  def create
    @policy = InvoicePolicyReview.new(policy_data: policy_data, created_by: Current.admin_user)
    persist_policy
  end

  def show
  end

  def update
    raise ActiveRecord::ReadOnlyRecord if @policy.approved?
    @policy.assign_attributes(policy_data: policy_data, status: :draft, configured_at: nil, lock_version: params.expect(:lock_version))
    persist_policy
  end

  def configure
    transition do
      @policy.assign_attributes(status: :configured, configured_at: Time.current)
    end
  end

  def approve
    unless params[:review_confirmed] == "1" && @policy.configured?
      return render plain: "Review the configured facts and confirm approval first.", status: :unprocessable_content
    end
    transition do
      @policy.assign_attributes(status: :approved, approved_by: Current.admin_user, approved_at: Time.current)
    end
  end

  def reopen
    return head :conflict unless @policy.configured?
    transition { @policy.assign_attributes(status: :draft, configured_at: nil) }
  end

  def duplicate
    draft = InvoicePolicyReview.create!(policy_data: @policy.policy_data.deep_dup, created_by: Current.admin_user, supersedes: @policy)
    redirect_to finance_policy_path(draft), notice: "New draft created. The earlier review is unchanged."
  end

  private
    def load_policy
      @policy = InvoicePolicyReview.find(params[:id])
    end

    def policy_data
      params.expect(policy_data: InvoicePolicyReview::FIELDS.keys).to_h.transform_values { |value| value.to_s.strip }
    end

    def transition
      raise ActiveRecord::ReadOnlyRecord if @policy.approved?
      @policy.lock_version = params.expect(:lock_version)
      yield
      persist_policy
    end

    def persist_policy
      if @policy.save
        redirect_to finance_policy_path(@policy), notice: "Review saved. Live issuance configuration has not changed."
      else
        render :show, status: :unprocessable_content
      end
    end
end
