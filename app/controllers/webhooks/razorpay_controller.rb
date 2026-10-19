module Webhooks
  class RazorpayController < ApplicationController
    allow_unauthenticated_access
    skip_forgery_protection

    def create
      raw = request.raw_post
      signature = request.headers["X-Razorpay-Signature"]
      event_id = request.headers["X-Razorpay-Event-Id"]
      return head :bad_request if signature.blank? || event_id.blank?

      secret = ENV.fetch("RAZORPAY_WEBHOOK_SECRET")
      begin
        Razorpay::Utility.verify_webhook_signature(raw, signature, secret)
        payload = JSON.parse(raw)

        handle_event(payload, event_id)
        head :ok
      rescue SecurityError
        record_signature_mismatch(raw)
        head :bad_request
      rescue JSON::ParserError, KeyError, TypeError
        head :bad_request
      end
    end

    private
      def handle_event(payload, event_id)
        case payload.fetch("event")
        when "order.paid", "payment.captured"
          process_payment(payload, event_id)
        when "payment.failed"
          record_failed_payment(payload, event_id)
        when "refund.processed"
          process_refund(payload, event_id)
        when "refund.failed"
          fail_refund(payload, event_id)
        end
      end

      def process_payment(payload, event_id)
        order = find_order(payload)
        return unless order

        event = record_event(order, payload, event_id)
        ConfirmOrderJob.perform_later(order.razorpay_order_id, event.id) if event
      end

      def record_failed_payment(payload, event_id)
        order = find_order(payload)
        record_event(order, payload, event_id) if order
      end

      def process_refund(payload, event_id)
        refund_entity = payload.dig("payload", "refund", "entity") || {}
        refund = Refund.legacy.find_by(razorpay_refund_id: refund_entity["id"])
        return unless refund

        refund.order.with_lock do
          event = record_event(refund.order, payload, event_id)
          if event
            job = ProcessRefundJob.perform_later(refund.id, event.id)
            raise ActiveJob::EnqueueError, "refund processing could not be enqueued" unless job
          end
        end
      end

      def fail_refund(payload, event_id)
        entity = payload.dig("payload", "refund", "entity") || {}
        refund = Refund.legacy.find_by(razorpay_refund_id: entity["id"])
        return unless refund && entity["amount"] == refund.amount_paise

        refund.fail!(event_id:, reason: "gateway_refund_failed")
      end

      def find_order(payload)
        payment = payload.dig("payload", "payment", "entity") || {}
        order = payload.dig("payload", "order", "entity") || {}
        Order.legacy.find_by(razorpay_order_id: payment["order_id"] || order["id"])
      end

      def record_event(order, payload, event_id)
        entity = payload.fetch("payload").each_value.filter_map { |value| value["entity"] }.first || {}
        PaymentEvent.record_webhook!(
          order:,
          event_id:,
          kind: payload.fetch("event"),
          amount_paise: entity["amount"] || entity["amount_paid"] || order.total_paise,
          raw: payload
        )
      end

      def record_signature_mismatch(raw)
        payload = JSON.parse(raw)
        return unless order = find_order(payload)

        order.payment_events.create!(
          razorpay_event_id: "signature_mismatch_#{SecureRandom.uuid}",
          kind: "signature_mismatch",
          level: "warn",
          amount_paise: order.total_paise,
          raw: { "event" => payload["event"] }
        )
      rescue JSON::ParserError
        nil
      end
  end
end
