class Finance::DocumentsController < Finance::BaseController
  before_action :load_order, except: :index
  rescue_from BillingDetails::Invalid, BillingDetails::Locked, BillingDetails::Stale, with: :billing_error

  def index
    pending = Order.where("metadata ->> 'invoice_pending_reason' IS NOT NULL OR metadata ->> 'confirmation_documents_pending' = 'true'")
      .or(Order.where(id: Refund.processed.where(credit_note_number: [ nil, "" ]).select(:order_id)))
    pending = Order.where(code: params[:code].to_s.strip.upcase) if params[:code].present?
    @page = [ params[:page].to_i, 1 ].max
    rows = pending.order(created_at: :asc).offset((@page - 1) * 25).limit(26).to_a
    @next_page = rows.size > 25
    @orders = rows.first(25)
  end

  def show
    prepare_details
  end

  def update
    return render plain: "Confirm that the billing facts were verified with the buyer.", status: :unprocessable_content unless params[:verified] == "1"
    BillingDetails.update_order!(@order, billing_params, source: "admin:#{Current.admin_user.id}", revision: params.expect(:billing_revision))
    redirect_to finance_document_path(@order), notice: "Billing facts saved. No document has been issued or rewritten."
  end

  def request_details
    @order.with_lock do
      raise BillingDetails::Locked, "An issued invoice cannot be changed through a billing link." if @order.invoices.exists?
      @order.update!(metadata: @order.metadata.merge("billing_request_nonce" => SecureRandom.hex(24)))
      @billing_link = billing_details_url(token: @order.generate_token_for(:billing_details))
    end
    prepare_details
    render :show
  end

  def retry_document
    review = InvoicePolicyReview.approved.order(approved_at: :desc).first
    unless params[:confirmed] == "1" && review&.runtime_matches?
      return render plain: "Retry requires explicit confirmation and an approved review matching separately configured runtime policy. Approval alone does not activate issuance.", status: :unprocessable_content
    end
    if params[:refund_id].present?
      refund = @order.refunds.find(params[:refund_id])
      return head :conflict unless refund.processed?
      event = @order.payment_events.find(params.expect(:payment_event_id))
      return head :unprocessable_content unless event.kind == "refund.processed" && event.amount_paise == refund.amount_paise
      raw_refund = event.raw.dig("payload", "refund", "entity", "id")
      unless event.razorpay_event_id == "free_refund_#{refund.id}" || (refund.razorpay_refund_id.present? && raw_refund == refund.razorpay_refund_id)
        return render plain: "Use the original processed event matching this refund.", status: :unprocessable_content
      end
      ProcessRefundJob.perform_later(refund.id, event.id)
    else
      return head :conflict unless @order.paid?
      GenerateOrderDocumentsJob.perform_later(@order)
    end
    redirect_to finance_document_path(@order), notice: "Document retry queued. Payment/refund processing is unchanged."
  end

  private
    def load_order
      @order = Order.find(params[:id])
    end

    def prepare_details
      @details = BillingDetails.for_order(@order)
      @review = InvoicePolicyReview.approved.order(approved_at: :desc).first
      @refund_events = @order.refunds.processed.to_h do |refund|
        events = @order.payment_events.where(kind: "refund.processed", amount_paise: refund.amount_paise).select do |event|
          event.razorpay_event_id == "free_refund_#{refund.id}" || (refund.razorpay_refund_id.present? && event.raw.dig("payload", "refund", "entity", "id") == refund.razorpay_refund_id)
        end
        [ refund.id, events ]
      end
    end

    def billing_params
      params.expect(billing: BillingDetails::FIELDS + BillingDetails::ORDER_FIELDS).to_h
    end

    def billing_error(error)
      prepare_details
      flash.now[:alert] = error.message
      render :show, status: error.is_a?(BillingDetails::Invalid) ? :unprocessable_content : :conflict
    end
end
