class BillingDetailsController < ApplicationController
  allow_unauthenticated_access
  layout "private_document"
  before_action :private_response
  before_action :load_order
  rate_limit to: 20, within: 1.minute, with: -> { head :too_many_requests }

  def show
    @details = BillingDetails.for_order(@order)
  end

  def update
    @order.with_lock do
      return head :not_found unless Order.find_by_token_for(:billing_details, params[:token]) && @order.metadata["billing_request_nonce"].present?
      BillingDetails.update_order!(@order, params.expect(billing: BillingDetails::FIELDS + BillingDetails::ORDER_FIELDS).to_h,
        source: "buyer_link", revision: params.expect(:billing_revision))
    end
    render :complete
  rescue BillingDetails::Invalid => error
    @details = BillingDetails.for_order(@order, params.expect(billing: BillingDetails::FIELDS + BillingDetails::ORDER_FIELDS).to_h)
    flash.now[:alert] = error.message
    render :show, status: :unprocessable_content
  rescue BillingDetails::Locked, BillingDetails::Stale
    render plain: "This billing request has changed or is closed. Contact the organizer for a new link.", status: :conflict
  end

  private
    def load_order
      @order = Order.find_by_token_for(:billing_details, params[:token].to_s)
      head :not_found unless @order && @order.metadata["billing_request_nonce"].present? && !@order.invoices.exists?
    end

    def private_response
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["Referrer-Policy"] = "no-referrer"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end
end
