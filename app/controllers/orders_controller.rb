class OrdersController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { redirect_to root_path, alert: "Please wait before trying again." }
  rate_limit to: 10, within: 1.minute, only: :show, name: "show", with: -> { redirect_to root_path, alert: "Please wait before trying again." }

  def create
    checkout = checkout_params
    order = Orders::Checkout.call(
      order_attributes: order_attributes(checkout),
      items: items(checkout),
      coupon_code: checkout[:coupon_code],
      conference_order_code: checkout[:conference_order_code],
      conference_order_email: checkout[:conference_order_email]
    )

    if order.total_paise < 100
      order.complete_comp!
      DeliverOrderConfirmationJob.perform_later(order)
    else
      order.create_razorpay_order!
    end
    @order = order
    render :checkout, status: :created
  rescue Orders::Checkout::SoldOut, Orders::Checkout::InvalidSelection, Orders::Checkout::ConferencePassRequired, Coupon::Invalid => error
    render_checkout_error(error.message)
  rescue ActiveRecord::RecordInvalid => error
    render_checkout_error(error.record.errors.full_messages.to_sentence)
  rescue Razorpay::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, SocketError, Ferrum::Error
    order&.update!(status: :expired) if order&.pending?
    render_checkout_error("We couldn't start checkout. Please try again.")
  end

  def show
    @order = Order.find_by!(code: params.expect(:code))
    @order.confirm_from_razorpay_if_stalled!
    regenerate_documents
  rescue ActiveRecord::RecordNotFound
    render file: Rails.root.join("public/404.html"), status: :not_found, layout: false
  end

  private
    def regenerate_documents
      return unless @order.paid?

      @order.attach_documents!
      @order.deliver_confirmation! if @order.metadata["confirmation_documents_pending"]
    rescue *ApplicationJob::DOCUMENT_ERRORS
      GenerateOrderDocumentsJob.perform_later(@order)
    end

    def render_checkout_error(message)
      @ticket_types = TicketType.where(hidden: false).order(:position, :id)
      flash.now[:alert] = message
      render "tickets/index", status: :unprocessable_content
    end

    def checkout_params
      params.expect(checkout: [
        :email, :buyer_name, :buyer_phone, :gstin, :gst_legal_name, :billing_state_code,
        :coupon_code, :conference_order_code, :conference_order_email, { quantities: {} }
      ])
    end

    def order_attributes(checkout)
      checkout.slice(:email, :buyer_name, :buyer_phone, :gstin, :gst_legal_name, :billing_state_code).to_h.symbolize_keys
    end

    def items(checkout)
      quantities = checkout.fetch(:quantities, {}).to_h
      items = quantities.filter_map do |ticket_type_id, quantity|
        ticket_type_id = Integer(ticket_type_id, exception: false)
        quantity = Integer(quantity, exception: false)
        next unless ticket_type_id&.positive? && ticket_type_id.bit_length <= 63 && quantity&.positive?

        { ticket_type_id:, quantity: }
      end
      hidden_ids = TicketType.where(id: items.pluck(:ticket_type_id), hidden: true).ids
      raise Orders::Checkout::InvalidSelection, "ticket type not found" if hidden_ids.any?

      items
    end
end
