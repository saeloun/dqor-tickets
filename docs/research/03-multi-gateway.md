# Multi-gateway payment abstraction with geo-based routing

Scope: dqor-tickets (Deccan Queen on Rails), a Rails event-ticketing app currently hard-wired to
Razorpay, INR-only, GST-aware. This document specifies how to introduce a ports-and-adapters
payment abstraction that supports Razorpay (India), Stripe (international), and PayU (India,
secondary), with automatic geo-based gateway/currency selection and a manual override — without
breaking the existing invoicing, refund, and reconciliation flows.

Grounded in the current codebase (read directly, not assumed):
`app/models/order.rb`, `app/models/payment_event.rb`, `app/models/refund.rb`,
`app/models/orders/checkout.rb`, `app/controllers/payments_controller.rb`,
`app/controllers/webhooks/razorpay_controller.rb`, `app/jobs/{confirm_order,initiate_refund,
process_refund,reconcile_payments}_job.rb`, `app/javascript/controllers/checkout_controller.js`,
`db/schema.rb`, `config/initializers/razorpay.rb`.

---

## 1. How the system works today (as-is)

This matters because the abstraction has to generalize *this*, not a green-field design:

- **Order creation** (`Orders::Checkout.call`) locks `TicketType` rows, prices everything in
  `price_paise` (INR paise, integer), applies a coupon, and creates a `pending` `Order` with a
  30-minute `expires_at` hold. No gateway call happens here.
- **Intent creation** (`Order#create_razorpay_order!`) is a *second* step, called from
  `OrdersController#create` right after the order row exists: it calls `Razorpay::Order.create`,
  stores `razorpay_order_id`, and logs a `PaymentEvent` (`kind: "order_created"`). Orders under
  ₹1 are auto-completed as "comp" orders and never touch Razorpay at all.
- **Client-side flow**: the `checkout.html.erb` view loads `checkout.js` v1 and boots a Stimulus
  controller (`checkout_controller.js`) that opens `new window.Razorpay({...}).open()` with the
  `order_id`, then on the `handler` callback auto-submits a hidden form with
  `razorpay_payment_id/order_id/signature` to `POST /payments/callback`.
- **Callback verification** (`PaymentsController#callback`) calls
  `Razorpay::Utility.verify_payment_signature` synchronously and records a `callback_verified`
  `PaymentEvent` — this is a UX fast-path only, **not** the source of truth for marking an order
  paid.
- **Webhook** (`Webhooks::RazorpayController`) is the actual source of truth: verifies
  `X-Razorpay-Signature` over the raw body, dedupes on `X-Razorpay-Event-Id`, and for
  `order.paid`/`payment.captured` enqueues `ConfirmOrderJob`, which calls `Order#mark_paid!`
  (idempotent via `with_lock` + status guard) and issues the GST invoice.
- **Reconciliation** (`ReconcilePaymentsJob` → `Order.reconcile_pending_payments!`) polls
  `Razorpay::Order.fetch(id).payments` for orders pending >2 minutes, as a safety net if the
  webhook never arrives. `Order#confirm_from_razorpay_if_stalled!` is a third safety net that
  fires from the `show` action if the client-side callback fired but no webhook/poll has landed
  in 30s.
- **Idempotency**: every write path funnels through `PaymentEvent.record_webhook!`, which does an
  `insert_all!` with a unique index on `razorpay_event_id` and rescues `RecordNotUnique` → `nil`.
  Refund creation uses a Razorpay-specific `X-Refund-Idempotency` header
  (`InitiateRefundJob::RefundRequest`) seeded from `refund.id`.
- **Refunds** (`Order#refund_tickets!` → `Refund` → `InitiateRefundJob` → webhook
  `refund.processed` → `ProcessRefundJob` → `Refund#process!`) cancel tickets, generate a credit
  note, and email it — gateway-specific only in `InitiateRefundJob`.
- **Money is INR paise everywhere**: `Order#total_paise`, `TicketType#price_paise`,
  `Invoice#line_items` (via `Gst.breakdown`), CSV exports, and the `inr()` view helper. GST
  (CGST/SGST/IGST) is computed per `billing_state_code`/`gstin` and assumes an Indian domestic
  sale throughout.

**The generalization has three layers of change**: (1) a gateway-neutral port interface with
per-gateway adapters, (2) a geo-based router that picks gateway+currency once, at order-creation
time, and stamps it immutably on the `Order`, and (3) schema changes that rename
Razorpay-specific columns to gateway-neutral ones and add multi-currency pricing — sequenced as
independent, low-risk migrations.

---

## 2. Gateway research

### 2.1 Razorpay (India: cards, UPI, netbanking, wallets) — current, keep as default for India

- **Order/intent creation**: `POST /v1/orders` (`Razorpay::Order.create(amount:, currency:,
  receipt:)`). `receipt` is the de-facto idempotency key — a second `create` with the same
  `receipt` is rejected, so seeding it with `order.code` (as today) gives free idempotency.
  Amount is in the smallest currency unit (paise for INR).
- **Client-side flow**: Checkout.js (hosted overlay) opens with the `order_id`; it renders
  card/UPI/netbanking/wallet tabs based on what's enabled on the merchant account; on success it
  invokes a JS `handler` with `razorpay_payment_id/order_id/signature`. No card data ever touches
  our server — PCI scope stays SAQ-A.
- **Webhook events** (subscribed today: `order.paid`, `payment.captured`, `payment.failed`,
  `refund.processed`; also relevant: `payment.authorized` for manual-capture flows,
  `refund.created`/`refund.failed`/`refund.speed_changed`, `payment.downtime.*`). Signature is
  HMAC-SHA256 over the raw body, verified via `Razorpay::Utility.verify_webhook_signature`, keyed
  separately from the API secret (`RAZORPAY_WEBHOOK_SECRET`). Dedupe via `X-Razorpay-Event-Id`.
- **Refunds**: `POST /v1/payments/{id}/refund`, idempotent via the `X-Refund-Idempotency` header
  (4–36 chars, alnum/hyphen/underscore) — exactly what `InitiateRefundJob` already does. Instant
  refunds are limited to tokenized VISA debit and a 4-day window; everything else settles via
  normal refund (T+5–7 days).
- **Saved cards / tokenization**: Razorpay TokenHQ is RBI-compliant Card-on-File Tokenisation
  (CoFT) — pass `save=true` on checkout with explicit consent; Razorpay stores a network token,
  never the PAN, scoped to (card, Razorpay-as-token-requestor, merchant). UPI Autopay handles
  recurring UPI mandates the same way, hosted entirely client-side.
- **Currencies**: INR primarily; supports 90+ currencies for select international card
  processing, but UPI/netbanking/wallets are INR/India-only by definition — this is why the geo
  router treats Razorpay as India-only in practice.
- **Fees** (2026 published rates): ~2% + 18% GST (≈2.36% effective) on cards/UPI/netbanking/
  wallets; ~3%+GST on EMI/corporate cards/Amex/Diners/Pay Later. No setup or AMC fees.

### 2.2 Stripe (international cards, Payment Intents, SetupIntents) — new, for non-India

- **Important constraint found in research**: Stripe does not currently offer general
  availability for Indian-domiciled merchant accounts processing domestic INR/UPI — as of this
  writing Stripe positions itself for cross-border/export use cases from India, doesn't issue
  FIRA/FEMA export documentation, and isn't a licensed PA-CB. **This is exactly why the geo router
  treats Stripe as the international-buyer gateway, not a India-domestic alternative to
  Razorpay** — it's the right tool for a US/EU/UK attendee paying in USD, not for UPI.
- **Order/intent creation**: `Stripe::PaymentIntent.create({amount:, currency:, ...},
  {idempotency_key:})`. Amount in smallest currency unit (cents for USD). The idempotency key is
  an explicit request option, not a body field — seed it deterministically
  (`"order-#{order.code}-intent"`) so retried requests during a flaky network are safe.
- **Client-side flow**: Stripe.js + Payment Element, `stripe.confirmPayment({elements,
  confirmParams: {return_url}})`. This is a redirect-capable flow (3DS/SCA), so unlike Razorpay's
  in-page callback, Stripe needs a `return_url` back into the app (`GET /payments/stripe/return`)
  in addition to the webhook.
- **Webhook events**: `payment_intent.succeeded`, `payment_intent.payment_failed`,
  `payment_intent.canceled`, `charge.refunded`, `charge.dispute.created`,
  `setup_intent.succeeded` (for saved-card enrollment without a charge). Verified via
  `Stripe::Webhook.construct_event(raw_body, sig_header, endpoint_secret)` — **must** use the raw
  request bytes, not `request.params`, exactly like the Razorpay controller already does with
  `request.raw_post`. Dedupe on `event.id` the same way `payment_events` dedupes on
  `razorpay_event_id` today.
- **Refunds**: `Stripe::Refund.create({payment_intent:, amount:}, {idempotency_key:})` — same
  idempotency-key-as-request-option pattern as intent creation.
- **Saved payment methods**: `Stripe::SetupIntent` collects and tokenizes a payment method
  against a `Stripe::Customer` *without* charging (e.g. to support future ticket purchases by a
  repeat international attendee); `Stripe::PaymentIntent.create({customer:, payment_method:,
  off_session: true, confirm: true, ...})` charges a saved method later. Off-session use requires
  documented upfront consent language (frequency, amount basis, cancellation policy) — same spirit
  as RBI's e-mandate consent requirement, different regulator.
- **Currencies**: 135+, multi-currency settlement supported. For this platform: USD as the
  default international currency, extensible to GBP/EUR later via the same `prices_minor` jsonb
  column (§4).
- **Fees**: base card rate + **1.5% international-card surcharge** + **1% currency-conversion
  fee** if settling in a currency different from the card's — these stack (e.g. a non-US card
  charged and settled in USD on a US-based Stripe account: ~2.9%+$0.30 base + 1.5% + 1% ≈ 5.4%+
  $0.30). Rates vary by the country the Stripe account itself is registered in. **Action item**:
  confirm which country the platform's Stripe account will be registered in before finalizing
  pricing — this changes both the fee stack and export-compliance posture above.

### 2.3 PayU (India, secondary/fallback)

- **Order/intent creation**: no REST "create order" object like Razorpay/Stripe — PayU is
  classically a **hash-signed form POST** to a hosted page. The merchant generates a `txnid`
  itself (this *is* the idempotency key — see §5) and a SHA-512 hash:
  `sha512(key|txnid|amount|productinfo|firstname|email|||||||||||SALT)`, then renders an
  auto-submitting HTML form to PayU's hosted checkout.
- **Client-side flow**: full-page redirect to PayU's hosted page (no JS SDK), then PayU redirects
  the browser back to a `surl`/`furl` (success/failure URL) with signed response params — this is
  the same shape as PayU's server-to-server webhook, both carry a `hash` field that must be
  recomputed and compared, not a header signature.
- **Webhook events**: PayU posts webhooks for success/failure/pending/refund/dispute to a
  configured URL; "pending" callbacks are opt-in (enabled by PayU support on request) which
  matters for reconciliation parity with Razorpay's polling fallback. Verify by recomputing the
  reverse hash `sha512(SALT|status|||||||||||email|firstname|productinfo|amount|txnid|key)` and
  comparing.
- **Refunds**: Refund Transaction API supports full and partial refunds against a captured
  transaction; request is hash-signed with `sha512(<body>|date|SALT)`. No dedicated idempotency
  header — dedupe must be app-level (§5).
- **Saved cards**: a separate "Save a Card" / tokenization API returns a card token stored in
  PayU's vault, RBI-compliant, consent + AFA required identically to Razorpay/Stripe.
- **Currencies**: primarily INR; some international acquiring exists but PayU India's core value
  is as a **second India-domestic rail** (redundancy/negotiating leverage against Razorpay,
  occasionally better netbanking/EMI coverage), not an international option.
- **Fees**: broadly comparable to Razorpay for domestic cards/UPI/netbanking (~2%), individually
  negotiated at volume.

### 2.4 Others, briefly

- **Cashfree**: REST Orders API (`POST /pg/orders`) closer in shape to Razorpay/Stripe than to
  PayU's hash-form pattern; webhook signature via `x-webhook-signature` (HMAC-SHA256, base64);
  competitive India-domestic pricing (~1.6–2%) with strong instant-settlement options. Would slot
  into the same adapter interface with the least friction of the "others" if a second India rail
  is ever needed instead of PayU.
- **Instamojo**: payment-request/redirect based, simplest integration, weakest webhook/API surface
  of the group, T+3 settlement (slowest here), best fit for very low-volume/no-website sellers —
  not recommended as a primary rail for this platform; mentioned only for completeness.

Neither needs an adapter built now; the interface in §3 is shaped so either becomes a ~150-line
adapter later without touching the router, models, or webhook processor.

---

## 3. Ports-and-adapters design (Ruby)

### 3.1 The port

One boundary interface every gateway adapter implements. Methods return small **value objects**
(`Payments::Result`, `Payments::WebhookEvent`), never raw gateway SDK objects — the whole point is
that `Order`, the webhook controller, and the jobs never `require "razorpay"` or `require
"stripe"` again.

```ruby
# app/models/payments/gateway.rb
module Payments
  # Port. Every adapter (RazorpayGateway, StripeGateway, PayuGateway, ...) implements this.
  # No method here may leak a gateway SDK object across the boundary.
  class Gateway
    class Error < StandardError; end
    class InvalidSignature < Error; end
    class NotSupported < Error; end
    class Transient < Error; end # network/5xx/429 — safe to retry via ApplicationJob::Retryable

    # @return [Symbol] :razorpay, :stripe, :payu, ...
    def name = raise NotImplementedError

    # @return [Array<Symbol>] currencies this adapter can settle, e.g. [:inr]
    def supported_currencies = raise NotImplementedError

    # Create the gateway-side order/intent for a pending Order. Idempotent per order.code.
    # @return [Payments::Intent] gateway_reference + whatever the client needs to render its widget
    def create_intent(order:) = raise NotImplementedError

    # Optional synchronous double-check of a client-side callback (Razorpay signature,
    # PayU surl hash). Gateways without one (Stripe: webhook + return_url is sufficient) no-op.
    # @return [Boolean]
    def verify_client_callback(params:) = raise NotImplementedError

    # Manual capture, for gateways/flows that authorize before capturing. Razorpay/PayU
    # auto-capture by default and may raise NotSupported here; Stripe implements it for real.
    def capture(payment_reference:, amount_minor: nil) = raise NotImplementedError

    # @return [Payments::Result] gateway_refund_id + status
    def refund(payment_reference:, amount_minor:, idempotency_key:) = raise NotImplementedError

    # Verify + normalize an inbound webhook. Must use the RAW request body for signature
    # verification (never parsed params) and must raise InvalidSignature on mismatch, never
    # silently return nil — callers decide what "invalid" means for logging.
    # @return [Payments::WebhookEvent]
    def verify_webhook(raw_body:, headers:, params: {}) = raise NotImplementedError

    # Poll the gateway directly for a captured payment against our own reference — the
    # reconciliation fallback path. Returns nil if nothing captured yet.
    # @return [Payments::WebhookEvent, nil]
    def fetch_captured_payment(gateway_reference:) = raise NotImplementedError

    # --- Saved-card / tokenization surface (all optional; see §6) ---
    def create_customer(email:) = raise NotSupported, "#{name} customer tokenization not implemented"
    def start_tokenization(customer_reference:) = raise NotSupported
    def charge_saved_method(customer_reference:, token_reference:, order:) = raise NotSupported
  end

  Intent = Struct.new(:gateway, :gateway_reference, :client_config, keyword_init: true)
  Result = Struct.new(:gateway, :gateway_reference, :status, :raw, keyword_init: true)

  # The normalized shape every adapter's verify_webhook / fetch_captured_payment returns.
  # `kind` is one of the gateway-neutral symbols below — this is what PaymentEvent stores,
  # not the gateway's own event name (which still lives in `raw` for audit/debugging).
  WebhookEvent = Struct.new(
    :gateway, :gateway_event_id, :gateway_payment_id, :gateway_reference,
    :kind, :amount_minor, :currency, :raw,
    keyword_init: true
  )

  KINDS = %i[order_paid payment_captured payment_failed refund_created refund_processed
             refund_failed signature_mismatch].freeze
end
```

### 3.2 Registry / router glue

```ruby
# app/models/payments/gateway_registry.rb
module Payments
  class GatewayRegistry
    ADAPTERS = {
      razorpay: -> { Payments::Gateways::RazorpayGateway.new },
      stripe:   -> { Payments::Gateways::StripeGateway.new },
      payu:     -> { Payments::Gateways::PayuGateway.new }
    }.freeze

    def self.for(gateway_name)
      ADAPTERS.fetch(gateway_name.to_sym) { raise ArgumentError, "unknown gateway #{gateway_name}" }.call
    end
  end
end
```

### 3.3 Razorpay adapter — how the *existing* flow generalizes

This is the important one: it shows the current `Order`/`InitiateRefundJob`/
`Webhooks::RazorpayController` code moved behind the port, near-verbatim, so the migration is a
mechanical extraction rather than a rewrite.

```ruby
# app/models/payments/gateways/razorpay_gateway.rb
module Payments
  module Gateways
    class RazorpayGateway < Payments::Gateway
      EVENT_KIND_MAP = {
        "order.paid" => :order_paid,
        "payment.captured" => :payment_captured,
        "payment.failed" => :payment_failed,
        "refund.created" => :refund_created,
        "refund.processed" => :refund_processed,
        "refund.failed" => :refund_failed
      }.freeze

      def name = :razorpay
      def supported_currencies = %i[inr]

      def create_intent(order:)
        razorpay_order = Razorpay::Order.create(
          amount: order.total_minor, currency: order.currency.upcase, receipt: order.code # receipt = idempotency key
        )
        Intent.new(
          gateway: :razorpay,
          gateway_reference: razorpay_order.id,
          client_config: { key: ENV.fetch("RAZORPAY_KEY_ID"), order_id: razorpay_order.id, currency: order.currency.upcase }
        )
      rescue Razorpay::ServerError, Razorpay::GatewayError => e
        raise Payments::Gateway::Transient, e.message
      end

      def verify_client_callback(params:)
        Razorpay::Utility.verify_payment_signature(
          razorpay_order_id: params.fetch(:razorpay_order_id),
          razorpay_payment_id: params.fetch(:razorpay_payment_id),
          razorpay_signature: params.fetch(:razorpay_signature)
        )
        true
      rescue SecurityError
        raise Payments::Gateway::InvalidSignature
      end

      def capture(payment_reference:, amount_minor: nil)
        raise Payments::Gateway::NotSupported, "Razorpay Standard Checkout auto-captures"
      end

      def refund(payment_reference:, amount_minor:, idempotency_key:)
        response = RefundRequest.new(idempotency_key).post("#{payment_reference}/refund", amount: amount_minor)
        Result.new(gateway: :razorpay, gateway_reference: response.id, status: response.status, raw: response.to_h)
      rescue Razorpay::Error => e
        raise Payments::Gateway::Transient, e.message if [409, 429].include?(e.status.to_i) || e.status.to_i >= 500
        raise
      end

      def verify_webhook(raw_body:, headers:, params: {})
        signature = headers["X-Razorpay-Signature"]
        event_id = headers["X-Razorpay-Event-Id"]
        raise Payments::Gateway::InvalidSignature if signature.blank? || event_id.blank?

        begin
          Razorpay::Utility.verify_webhook_signature(raw_body, signature, ENV.fetch("RAZORPAY_WEBHOOK_SECRET"))
        rescue SecurityError
          raise Payments::Gateway::InvalidSignature
        end

        payload = JSON.parse(raw_body)
        entity = payload.fetch("payload").each_value.filter_map { |v| v["entity"] }.first || {}
        payment = payload.dig("payload", "payment", "entity") || {}
        order_entity = payload.dig("payload", "order", "entity") || {}

        WebhookEvent.new(
          gateway: :razorpay,
          gateway_event_id: event_id,
          gateway_payment_id: payment["id"],
          gateway_reference: payment["order_id"] || order_entity["id"],
          kind: EVENT_KIND_MAP.fetch(payload.fetch("event"), :unhandled),
          amount_minor: entity["amount"] || entity["amount_paid"],
          currency: (entity["currency"] || "INR").downcase,
          raw: payload
        )
      end

      def fetch_captured_payment(gateway_reference:)
        payment = Array(Razorpay::Order.fetch(gateway_reference).payments.items)
          .find { |item| item["captured"] || item["status"] == "captured" }
        return nil unless payment

        WebhookEvent.new(
          gateway: :razorpay, gateway_event_id: "reconcile_#{payment.fetch('id')}",
          gateway_payment_id: payment.fetch("id"), gateway_reference:,
          kind: :payment_captured, amount_minor: payment.fetch("amount"),
          currency: (payment["currency"] || "INR").downcase, raw: payment
        )
      rescue Razorpay::Error => e
        raise Payments::Gateway::Transient, e.message if e.status.to_i == 429 || e.status.to_i >= 500
        raise
      end

      class RefundRequest < Razorpay::Request
        def initialize(idempotency_key)
          super("payments")
          @options[:headers]["X-Refund-Idempotency"] = idempotency_key
        end
      end
      private_constant :RefundRequest
    end
  end
end
```

Everything in that class is a direct lift of logic already in `Order`, `InitiateRefundJob`, and
`Webhooks::RazorpayController` today — nothing new is invented, it is *relocated* behind the
port and its gateway-specific strings (`"order.paid"`) are translated to the neutral `KINDS` once,
at the boundary, instead of being switched on deep inside a controller.

### 3.4 Stripe adapter (new)

```ruby
# app/models/payments/gateways/stripe_gateway.rb
module Payments
  module Gateways
    class StripeGateway < Payments::Gateway
      EVENT_KIND_MAP = {
        "payment_intent.succeeded" => :payment_captured,
        "payment_intent.payment_failed" => :payment_failed,
        "charge.refunded" => :refund_processed,
        "charge.dispute.created" => :unhandled # surfaced to Slack/ops, not auto-processed
      }.freeze

      def name = :stripe
      def supported_currencies = %i[usd gbp eur]

      def create_intent(order:)
        intent = Stripe::PaymentIntent.create(
          { amount: order.total_minor, currency: order.currency,
            metadata: { order_code: order.code },
            automatic_payment_methods: { enabled: true } },
          { idempotency_key: "order-#{order.code}-intent" }
        )
        Intent.new(
          gateway: :stripe, gateway_reference: intent.id,
          client_config: { publishable_key: ENV.fetch("STRIPE_PUBLISHABLE_KEY"), client_secret: intent.client_secret }
        )
      rescue Stripe::APIConnectionError, Stripe::APIError => e
        raise Payments::Gateway::Transient, e.message
      end

      # Stripe's Payment Element + 3DS redirect makes the client-side callback redundant —
      # confirmation is via webhook + the return_url page, which just re-renders order#show.
      def verify_client_callback(params:) = true

      def capture(payment_reference:, amount_minor: nil)
        intent = Stripe::PaymentIntent.capture(payment_reference, amount_minor ? { amount_to_capture: amount_minor } : {})
        Result.new(gateway: :stripe, gateway_reference: intent.id, status: intent.status, raw: intent.to_hash)
      end

      def refund(payment_reference:, amount_minor:, idempotency_key:)
        refund = Stripe::Refund.create({ payment_intent: payment_reference, amount: amount_minor }, { idempotency_key: })
        Result.new(gateway: :stripe, gateway_reference: refund.id, status: refund.status, raw: refund.to_hash)
      rescue Stripe::APIConnectionError, Stripe::RateLimitError => e
        raise Payments::Gateway::Transient, e.message
      end

      def verify_webhook(raw_body:, headers:, params: {})
        event = Stripe::Webhook.construct_event(raw_body, headers["Stripe-Signature"], ENV.fetch("STRIPE_WEBHOOK_SECRET"))
        object = event.data.object

        WebhookEvent.new(
          gateway: :stripe, gateway_event_id: event.id,
          gateway_payment_id: object.respond_to?(:payment_intent) ? object.payment_intent : object.id,
          gateway_reference: object.id,
          kind: EVENT_KIND_MAP.fetch(event.type, :unhandled),
          amount_minor: object.amount, currency: object.currency,
          raw: event.to_hash
        )
      rescue Stripe::SignatureVerificationError
        raise Payments::Gateway::InvalidSignature
      end

      def fetch_captured_payment(gateway_reference:)
        intent = Stripe::PaymentIntent.retrieve(gateway_reference)
        return nil unless intent.status == "succeeded"

        WebhookEvent.new(
          gateway: :stripe, gateway_event_id: "reconcile_#{intent.id}",
          gateway_payment_id: intent.latest_charge, gateway_reference: intent.id,
          kind: :payment_captured, amount_minor: intent.amount, currency: intent.currency, raw: intent.to_hash
        )
      rescue Stripe::APIConnectionError, Stripe::RateLimitError => e
        raise Payments::Gateway::Transient, e.message
      end

      # --- saved payment methods (SetupIntents) ---
      def create_customer(email:)
        customer = Stripe::Customer.create({ email: }, { idempotency_key: "customer-#{email}" })
        Result.new(gateway: :stripe, gateway_reference: customer.id, status: "created", raw: customer.to_hash)
      end

      def start_tokenization(customer_reference:)
        setup_intent = Stripe::SetupIntent.create(customer: customer_reference, usage: "off_session")
        Intent.new(gateway: :stripe, gateway_reference: setup_intent.id,
                    client_config: { client_secret: setup_intent.client_secret })
      end

      def charge_saved_method(customer_reference:, token_reference:, order:)
        intent = Stripe::PaymentIntent.create(
          { amount: order.total_minor, currency: order.currency, customer: customer_reference,
            payment_method: token_reference, off_session: true, confirm: true },
          { idempotency_key: "order-#{order.code}-saved-charge" }
        )
        Result.new(gateway: :stripe, gateway_reference: intent.id, status: intent.status, raw: intent.to_hash)
      rescue Stripe::CardError => e # off-session auth required — caller must fall back to a fresh checkout
        Result.new(gateway: :stripe, gateway_reference: nil, status: "requires_action", raw: { "error" => e.message })
      end
    end
  end
end
```

### 3.5 PayU adapter (new) — the shape that differs most

PayU has no order object and no header-signature webhook, so `create_intent`'s `client_config`
carries the whole signed form, and `verify_webhook` recomputes a hash instead of calling an SDK
verifier:

```ruby
# app/models/payments/gateways/payu_gateway.rb
module Payments
  module Gateways
    class PayuGateway < Payments::Gateway
      def name = :payu
      def supported_currencies = %i[inr]

      def create_intent(order:)
        txnid = "dqor-#{order.code}" # our own idempotency boundary — see §5
        amount = format("%.2f", order.total_minor / 100.0)
        fields = {
          key: ENV.fetch("PAYU_MERCHANT_KEY"), txnid:, amount:, productinfo: "DQOR tickets",
          firstname: order.buyer_name, email: order.email, phone: order.buyer_phone,
          surl: Rails.application.routes.url_helpers.payu_return_url(status: "success"),
          furl: Rails.application.routes.url_helpers.payu_return_url(status: "failure")
        }
        fields[:hash] = hash_request(fields)
        Intent.new(gateway: :payu, gateway_reference: txnid,
                    client_config: { post_url: ENV.fetch("PAYU_BASE_URL"), fields: })
      end

      # PayU's surl/furl redirect and its webhook carry the same signed shape — both are
      # verified by recomputing the reverse hash, no SDK/header involved.
      def verify_client_callback(params:)
        expected = reverse_hash(params)
        ActiveSupport::SecurityUtils.secure_compare(expected, params.fetch(:hash))
      end

      def capture(payment_reference:, amount_minor: nil)
        raise Payments::Gateway::NotSupported, "PayU standard flow auto-captures"
      end

      def refund(payment_reference:, amount_minor:, idempotency_key:)
        # idempotency_key is app-level only (§5) — PayU's Refund API has no idempotency header
        response = PayuClient.post("/refund", { txnid: payment_reference, amount: amount_minor / 100.0 })
        Result.new(gateway: :payu, gateway_reference: response["request_id"], status: response["status"], raw: response)
      end

      def verify_webhook(raw_body:, headers:, params: {})
        raise Payments::Gateway::InvalidSignature unless verify_client_callback(params: params)

        WebhookEvent.new(
          gateway: :payu, gateway_event_id: "#{params[:txnid]}_#{params[:status]}",
          gateway_payment_id: params[:mihpayid], gateway_reference: params[:txnid],
          kind: params[:status] == "success" ? :payment_captured : :payment_failed,
          amount_minor: (params[:amount].to_f * 100).round, currency: "inr", raw: params.to_unsafe_h
        )
      end

      def fetch_captured_payment(gateway_reference:)
        response = PayuClient.get("/verify_payment", { txnid: gateway_reference })
        row = response.dig("transaction_details", gateway_reference)
        return nil unless row && row["status"] == "success"

        WebhookEvent.new(
          gateway: :payu, gateway_event_id: "reconcile_#{gateway_reference}",
          gateway_payment_id: row["mihpayid"], gateway_reference:,
          kind: :payment_captured, amount_minor: (row["amt"].to_f * 100).round, currency: "inr", raw: row
        )
      end

      private
        def hash_request(f)
          Digest::SHA512.hexdigest("#{f[:key]}|#{f[:txnid]}|#{f[:amount]}|#{f[:productinfo]}|#{f[:firstname]}|#{f[:email]}|||||||||||#{ENV.fetch('PAYU_SALT')}")
        end

        def reverse_hash(p)
          Digest::SHA512.hexdigest("#{ENV.fetch('PAYU_SALT')}|#{p[:status]}|||||||||||#{p[:email]}|#{p[:firstname]}|#{p[:productinfo]}|#{p[:amount]}|#{p[:txnid]}|#{ENV.fetch('PAYU_MERCHANT_KEY')}")
        end
    end
  end
end
```

---

## 4. Data model changes

Sequenced as **independent migrations**, each safe to ship and roll back alone. New columns are
additive/nullable first; drop of the old Razorpay-specific columns happens in a follow-up
migration once every read path has moved to the new ones — normal expand/contract.

```ruby
# 1) Orders: which gateway/currency this order was created against, generalized reference.
class AddGatewayToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :gateway, :string, null: false, default: "razorpay"
    add_column :orders, :currency, :string, null: false, default: "inr"
    add_column :orders, :gateway_reference, :string   # generalizes razorpay_order_id
    add_column :orders, :country, :string, limit: 2    # CF-IPCountry snapshot at order-creation time, for audit/pricing disputes
    add_index :orders, [:gateway, :gateway_reference], unique: true
  end
end

# Backfill (separate data migration / rake task, batched):
#   Order.where(gateway_reference: nil).where.not(razorpay_order_id: nil)
#        .in_batches.update_all("gateway_reference = razorpay_order_id")
# razorpay_order_id stays read-only for historical orders until dropped in a later migration.

# 2) PaymentEvent: generalize the Razorpay-prefixed identity columns.
class AddGatewayToPaymentEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :payment_events, :gateway, :string, null: false, default: "razorpay"
    add_column :payment_events, :gateway_event_id, :string
    add_column :payment_events, :gateway_payment_id, :string
    add_index :payment_events, [:gateway, :gateway_event_id], unique: true
    add_index :payment_events, [:gateway, :gateway_payment_id], unique: true,
              where: "gateway_payment_id IS NOT NULL"
  end
end
# Backfill gateway_event_id/gateway_payment_id from razorpay_event_id/razorpay_payment_id,
# then in a later migration: remove_column :payment_events, :razorpay_event_id (etc.)
# and rename gateway_event_id -> the canonical name once nothing references the old one.

# 3) Refund: same generalization.
class AddGatewayToRefunds < ActiveRecord::Migration[8.0]
  def change
    add_column :refunds, :gateway, :string, null: false, default: "razorpay"
    add_column :refunds, :gateway_refund_id, :string
    add_index :refunds, [:gateway, :gateway_refund_id], unique: true, where: "gateway_refund_id IS NOT NULL"
  end
end

# 4) TicketType: multi-currency price list instead of a single INR column.
class AddPricesMinorToTicketTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :ticket_types, :prices_minor, :jsonb, null: false, default: {}
    # e.g. {"inr" => 500000, "usd" => 6000} — minor units, admin-managed, no live FX call
    # in the checkout critical path. price_paise stays as the INR source of truth during
    # transition; TicketType#price_minor(currency) reads prices_minor, falling back to
    # {"inr" => price_paise} for rows not yet migrated.
  end
end

# 5) Saved-card / tokenization surface (only needed once repeat-purchase is prioritized — see §6)
class CreateGatewayCustomersAndPaymentMethods < ActiveRecord::Migration[8.0]
  def change
    create_table :gateway_customers do |t|
      t.string :gateway, null: false
      t.string :email, null: false
      t.string :gateway_customer_id, null: false
      t.timestamps
    end
    add_index :gateway_customers, [:gateway, :email], unique: true

    create_table :payment_methods do |t|
      t.references :gateway_customer, null: false, foreign_key: true
      t.string :gateway, null: false
      t.string :token_reference, null: false        # Stripe PaymentMethod ID / Razorpay/PayU network token
      t.string :card_network                         # visa/mastercard/rupay/amex
      t.string :card_last4
      t.integer :card_exp_month
      t.integer :card_exp_year
      t.boolean :is_network_token, null: false, default: true # false only if a gateway ever returns a non-CoFT reference
      t.string :status, null: false, default: "active" # active/revoked/expired
      t.datetime :consent_captured_at, null: false     # RBI/Stripe both require explicit, logged consent
      t.timestamps
    end
    add_index :payment_methods, [:gateway, :token_reference], unique: true
  end
end
```

**On renaming `total_paise`**: leave it alone in this change. It's read in `Gst.breakdown`,
`Invoice`, CSV exports, mailers, and the `inr()` view helper — a rename is a large mechanical diff
that has nothing to do with multi-gateway support and should not share a PR (or a review) with the
adapter work. Land it as its own follow-up (`total_paise` → `total_minor_units`, with a deprecated
`total_paise` alias method during transition) once the currency work is otherwise proven. Same
logic applies to the `inr()` helper — generalize it to `money(order)` (dispatches on
`order.currency`) in that same follow-up, not here.

**GST implication, flagged not solved**: `Gst.breakdown` assumes every sale is a domestic Indian
supply. A Stripe/USD order to a non-resident buyer is very likely an *export of service*
(zero-rated under LUT, no CGST/SGST/IGST line items) rather than a domestic taxable supply — this
needs sign-off from Finance/CA, not an engineering guess. Proposed hook: `Invoice.issue_for!`
branches on `order.gateway == "razorpay"` (apply `Gst.breakdown` as today) vs. anything else (skip
GST, mark the invoice as an export line item) — but the actual tax treatment, whether FIRC/BRC
documentation is needed per transaction, and Stripe's lack of PA-CB/FIRA support (§2.2) are
compliance questions to close before Stripe goes live, not implementation details.

---

## 5. Idempotency, unified

Two independent idempotency problems, both already partially solved today and now generalized:

**Outbound (our server → gateway)** — prevent double-charging on retried requests (job retries,
flaky networks, double form submits):

| Gateway | Mechanism | Seed |
|---|---|---|
| Razorpay orders | `receipt` field (native) | `order.code` |
| Razorpay refunds | `X-Refund-Idempotency` header | `"dqor-refund-#{refund.id}"` |
| Stripe intents/refunds | `idempotency_key` request option | `"order-#{order.code}-intent"` / `"refund-#{refund.id}"` |
| PayU | none native — app-level only | deterministic `txnid = "dqor-#{order.code}"`, unique-indexed on `orders(gateway, gateway_reference)` so a second `create_intent` for the same order is a DB-level no-op before any PayU call happens |

**Inbound (gateway → our server, webhooks)** — already solved generically and doesn't need to
change shape, only widen: `PaymentEvent.record_webhook!` keeps doing an `insert_all!` +
`rescue ActiveRecord::RecordNotUnique => nil`, now against the unique index on
`(gateway, gateway_event_id)` instead of `razorpay_event_id` alone. This is the one piece of the
existing design that was *already* gateway-agnostic in spirit — Stripe's `event.id` and PayU's
synthesized `"#{txnid}_#{status}"` slot into the same column with zero new logic.

```ruby
# app/models/payment_event.rb (generalized)
def self.record_webhook!(order:, webhook_event:)
  now = Time.current
  result = transaction(requires_new: true) do
    insert_all!([{
      order_id: order.id,
      gateway: webhook_event.gateway,
      gateway_event_id: webhook_event.gateway_event_id,
      gateway_payment_id: webhook_event.gateway_payment_id,
      kind: webhook_event.kind,
      level: "info",
      mode: gateway_mode(webhook_event.gateway),
      amount_paise: webhook_event.amount_minor,
      raw: webhook_event.raw,
      created_at: now, updated_at: now
    }], returning: %w[id])
  end
  find(result.rows.sole.sole)
rescue ActiveRecord::RecordNotUnique
  nil
end
```

---

## 6. Normalized webhook processing (one controller, not three)

```ruby
# config/routes.rb
namespace :webhooks do
  resources :gateways, only: :create, param: :gateway  # POST /webhooks/gateways/:gateway
end

# app/controllers/webhooks/gateways_controller.rb
module Webhooks
  class GatewaysController < ApplicationController
    allow_unauthenticated_access
    skip_forgery_protection

    def create
      gateway = Payments::GatewayRegistry.for(params[:gateway])
      event = gateway.verify_webhook(raw_body: request.raw_post, headers: request.headers, params: request.params)
      Payments::WebhookProcessor.new(event).call
      head :ok
    rescue Payments::Gateway::InvalidSignature
      record_signature_mismatch(params[:gateway])
      head :bad_request
    rescue ArgumentError, JSON::ParserError
      head :bad_request
    end

    private
      def record_signature_mismatch(gateway)
        # best-effort audit trail; must not raise
      end
  end
end

# app/models/payments/webhook_processor.rb — the gateway-neutral version of
# Webhooks::RazorpayController#handle_event, unchanged in spirit, switching on Payments::KINDS
# instead of raw gateway event strings.
module Payments
  class WebhookProcessor
    def initialize(event) = @event = event

    def call
      case @event.kind
      when :order_paid, :payment_captured then process_payment
      when :payment_failed then record_failed_payment
      when :refund_processed then process_refund
      else nil # refund_created / unhandled are logged via record_webhook! but don't drive a job
      end
    end

    private
      def process_payment
        order = Order.find_by(gateway: @event.gateway, gateway_reference: @event.gateway_reference)
        return unless order

        payment_event = PaymentEvent.record_webhook!(order:, webhook_event: @event)
        ConfirmOrderJob.perform_later(order.id, payment_event.id) if payment_event
      end

      def record_failed_payment
        order = Order.find_by(gateway: @event.gateway, gateway_reference: @event.gateway_reference)
        PaymentEvent.record_webhook!(order:, webhook_event: @event) if order
      end

      def process_refund
        refund = Refund.find_by(gateway: @event.gateway, gateway_refund_id: @event.gateway_payment_id)
        return unless refund

        payment_event = PaymentEvent.record_webhook!(order: refund.order, webhook_event: @event)
        ProcessRefundJob.perform_later(refund.id, payment_event.id) if payment_event
      end
  end
end
```

`ConfirmOrderJob` changes its lookup key from `razorpay_order_id:` to `id:` (looking the order up
by its own primary key, passed through from the webhook processor, rather than re-deriving it from
a gateway-specific column) — this removes a gateway assumption from the job entirely rather than
generalizing it.

`Order#mark_paid!`, `Order#refund_tickets!`, `Order#reconcile_payment!`,
`Order#confirm_from_razorpay_if_stalled!` all become one-line dispatches to
`Payments::GatewayRegistry.for(gateway)` instead of calling `Razorpay::Order`/`Razorpay::Utility`
directly — e.g.:

```ruby
# app/models/order.rb (relevant excerpt)
def create_gateway_intent!
  return self if gateway_reference?
  return complete_comp! if total_minor < 100

  intent = payment_gateway.create_intent(order: self)
  update!(gateway_reference: intent.gateway_reference)
  payment_events.create!(gateway:, gateway_event_id: "order_created_#{intent.gateway_reference}",
                          kind: "order_created", amount_paise: total_minor, raw: { "gateway_reference" => intent.gateway_reference })
  self
end

def reconcile_payment!
  return unless pending? && gateway_reference?

  event = payment_gateway.fetch_captured_payment(gateway_reference:)
  return unless event

  payment_event = PaymentEvent.record_webhook!(order: self, webhook_event: event)
  ConfirmOrderJob.perform_now(id, payment_event.id) if payment_event
rescue Payments::Gateway::Transient => e
  record_polling_failure(e)
  raise
end

private
  def payment_gateway = Payments::GatewayRegistry.for(gateway)
```

`Order.reconcilable` scope generalizes from `.where.not(razorpay_order_id: nil)` to
`.where.not(gateway_reference: nil)` — no other change needed, it already iterates gateway-
agnostically via `find_each(&:reconcile_payment!)`.

---

## 7. Geo-based routing

### 7.1 Detection → decision, resolved once, at order-creation time

The single most important architectural rule: **the routing decision is made exactly once, when
`Orders::Checkout.call` creates the `Order` row, and is then immutable** (`gateway`, `currency`,
`country` are stamped on the order). Every downstream path — webhook processing, reconciliation,
refunds, the `show` action — reads `order.gateway`, never re-runs geo detection. This mirrors how
`total_paise` is already frozen at order-creation and never recomputed later; routing gets the same
treatment for the same reason (a buyer's IP/locale can change mid-session; an order's payment rail
must not).

```ruby
# app/models/payments/router.rb
module Payments
  class Router
    GATEWAY_BY_COUNTRY = { "IN" => :razorpay }.freeze
    DEFAULT_GATEWAY = :stripe # everyone not explicitly mapped above
    CURRENCY_BY_GATEWAY = { razorpay: "inr", payu: "inr", stripe: "usd" }.freeze
    OVERRIDABLE_GATEWAYS = %i[razorpay stripe].freeze # payu stays reconciliation/ops-triggered only, not user-selectable yet

    Decision = Struct.new(:gateway, :currency, :country, keyword_init: true)

    def self.resolve(request:, override_param: nil)
      country = detect_country(request)
      gateway = override_gateway(override_param) || GATEWAY_BY_COUNTRY.fetch(country, DEFAULT_GATEWAY)
      Decision.new(gateway:, currency: CURRENCY_BY_GATEWAY.fetch(gateway), country:)
    end

    def self.detect_country(request)
      cf_country = request.headers["CF-IPCountry"]
      return cf_country if cf_country.present? && cf_country != "XX" # XX = Cloudflare's "unknown" sentinel
      accept_language_country(request) || "IN" # default to India, this platform's home market
    end

    def self.override_gateway(param)
      candidate = param.to_s.downcase.to_sym
      candidate if OVERRIDABLE_GATEWAYS.include?(candidate)
    end

    def self.accept_language_country(request)
      # "en-IN,en;q=0.9" -> "IN" — a weak secondary signal, only used when CF-IPCountry is absent
      # (e.g. local dev, or Cloudflare IP Geolocation toggled off) and never overrides a real
      # country header. Deliberately not used for currency/pricing decisions, only gateway choice.
      request.headers["Accept-Language"].to_s[/[a-z]{2}-([A-Z]{2})/, 1]
    end
  end
end
```

### 7.2 Wiring into the two touchpoints that need it

**Ticket-selection page (pricing display)** — resolve country/currency before render, so prices
shown match what checkout will actually charge:

```ruby
# app/controllers/tickets_controller.rb (excerpt)
before_action :resolve_payment_routing

def resolve_payment_routing
  @routing = Payments::Router.resolve(request:, override_param: params[:pay_with] || cookies[:gateway_override])
  cookies[:gateway_override] = { value: @routing.gateway, expires: 1.day } if params[:pay_with].present?
end
```

Template shows a plain-text toggle, not a dropdown buried in settings — e.g. *"Prices in ₹ (India)
· [Pay in USD instead →]"* linking to `?pay_with=stripe`, and the reverse link once switched. This
directly answers "how to present the right option": default silently to the geo-detected gateway
(no interstitial, no popup) and offer one explicit, reversible link for the edge case (VPN users,
Indians living abroad who want to avoid FX fees, international attendees Cloudflare
mis-geolocates).

**Order creation** — `Orders::Checkout.call` takes the resolved `Decision` and stamps it:

```ruby
# app/controllers/orders_controller.rb (excerpt)
def create
  checkout = checkout_params
  routing = Payments::Router.resolve(request:, override_param: cookies[:gateway_override])
  order = Orders::Checkout.call(
    order_attributes: order_attributes(checkout).merge(gateway: routing.gateway, currency: routing.currency, country: routing.country),
    items: items(checkout), coupon_code: checkout[:coupon_code], ...
  )
  order.total_paise < 100 ? order.complete_comp! : order.create_gateway_intent!
  ...
```

`Orders::Checkout#call` prices from `TicketType#price_minor(order.currency)` instead of
`price_paise` directly — the one line that changes in that service object.

### 7.3 Presenting the right client-side flow

`orders/checkout.html.erb` branches once on `@order.gateway`, each branch loading only its own
script and Stimulus controller — Razorpay's Checkout.js stays exactly as-is; Stripe adds
`stripe_checkout_controller.js` (Stripe.js + Payment Element +
`stripe.confirmPayment({elements, confirmParams: {return_url: order_return_url}})`); PayU needs no
JS at all — its `client_config` from `create_intent` is rendered directly as a hidden
auto-submitting `<form>` POSTing to `PAYU_BASE_URL`, matching PayU's redirect-only nature from
§2.3/§3.5.

---

## 8. Saved cards across gateways given RBI CoFT constraints

The current app is already at the safest possible starting point: **it has never touched card data
of any kind** — Razorpay Checkout.js is fully hosted, and this platform has no buyer login/account
system (buyers are matched by order code + email via `TicketAccessController`). Adding Stripe
Elements/Payment Element preserves that (also fully hosted, PCI SAQ-A). So saved-card support is
purely additive scope, not a compliance gap being introduced.

If/when repeat-purchase support is prioritized (e.g. a returning attendee for next year's event):

- **RBI mandates Card-on-File Tokenisation for every India-issued card** — the merchant may never
  store PAN/CVV/expiry, only a **network token scoped to (card, token requestor, merchant)**, with
  explicit customer consent captured per save (`save=true` on Razorpay Checkout, PayU's Save-a-Card
  API) and Additional Factor Authentication (2FA) at the time of tokenization *and* at time of use.
  Razorpay TokenHQ and PayU's card vault both produce this shape natively — no custom PCI
  infrastructure is ever required on our side, because the token itself is useless outside the
  (card, requestor, merchant) triple it was minted for.
- **Stripe's model is architecturally different but equivalent in spirit**: a `Stripe::Customer` +
  `Stripe::PaymentMethod` pair, created via `SetupIntent`, is Stripe's own vault-and-token
  abstraction — not RBI-regulated (Stripe/international cards aren't in RBI's CoFT scope), but
  Stripe independently requires documented consent language for off-session use (§2.2), which is
  the same operational discipline (log consent, timestamp it) even though the legal basis differs.
- **The `payment_methods` table (§4) is deliberately gateway-symmetric**: `token_reference` holds
  whatever opaque reference each gateway returns (Razorpay/PayU network token, Stripe
  `pm_...` ID), `consent_captured_at` is mandatory on every row regardless of gateway, and no
  column anywhere in this schema is capable of holding a PAN — the interface (`charge_saved_method`
  taking a `token_reference`, never card fields) makes storing raw card data structurally
  impossible, not just policy-discouraged.
- **Cross-gateway reuse doesn't exist and shouldn't be attempted**: a Razorpay network token cannot
  be charged via Stripe or vice versa — they are different vaults with different regulatory bases.
  A returning buyer who paid via Razorpay last year and is now routed to Stripe this year (moved
  abroad) simply re-tokenizes fresh; `gateway_customers` is keyed on `(gateway, email)` precisely
  so this is a non-event rather than a migration.
- **Practical scope note**: given this is a low-frequency-purchase ticketing platform (one or two
  orders per attendee per year) rather than a subscription business, the ROI on building saved-card
  UX at all is questionable next to just re-running Checkout.js/Payment Element each time — this
  section is written to be ready if product decides it's worth it, not as a recommendation to build
  it now.

---

## 9. Rollout sequencing

1. **Schema migrations** (§4, additive/nullable only) — ship and backfill independently of any
   behavior change; `gateway` defaults to `"razorpay"` so existing rows and existing code paths are
   untouched.
2. **Extract `Payments::Gateway` + `RazorpayGateway`** (§3.1, §3.3) behind the existing behavior —
   `Order`, jobs, and the webhook controller start calling the adapter instead of `Razorpay::*`
   directly, with **zero observable behavior change**. This is the PR to review hardest, since it's
   a pure refactor and any diff in behavior here is a bug, not a feature.
3. **Generalize the webhook controller and `PaymentEvent`/`Refund` columns** (§6) — still
   Razorpay-only in practice, but now gateway-neutral in shape. Verify with the existing webhook
   spec suite (`spec/requests/webhooks/razorpay_spec.rb`) pointed at the new route.
4. **Add `Payments::Router`** (§7) with `GATEWAY_BY_COUNTRY = {"IN" => :razorpay}` and
   `DEFAULT_GATEWAY = :razorpay` (not `:stripe` yet) — routing infrastructure ships dark, every
   order still resolves to Razorpay, fully reversible.
5. **Build `StripeGateway`** (§3.4) behind a feature flag / env-gated `DEFAULT_GATEWAY`, test
   end-to-end in Stripe test mode, resolve the Stripe-account-country/export-compliance question
   from §2.2 with Finance before this step ships to production traffic.
6. **Flip `DEFAULT_GATEWAY` to `:stripe`** for real, monitor `payment_events` by `gateway` in Avo
   for a currency-mix sanity check (`PaymentEvent` already has an Avo resource —
   `app/avo/resources/payment_event.rb` — add a `gateway` column filter there).
7. **PayU / Cashfree adapters** — build only if/when a second India-domestic rail becomes a real
   business need (negotiating leverage, Razorpay outage redundancy); the interface is already
   shaped for it, so this is additive at any point after step 2.

---

## Summary of key files this design touches

- New: `app/models/payments/gateway.rb`, `app/models/payments/gateway_registry.rb`,
  `app/models/payments/router.rb`, `app/models/payments/webhook_processor.rb`,
  `app/models/payments/gateways/{razorpay,stripe,payu}_gateway.rb`
- Changed: `app/models/order.rb`, `app/models/payment_event.rb`, `app/models/refund.rb`,
  `app/models/orders/checkout.rb`, `app/models/ticket_type.rb`,
  `app/controllers/orders_controller.rb`, `app/controllers/payments_controller.rb`,
  `app/controllers/webhooks/gateways_controller.rb` (replaces `webhooks/razorpay_controller.rb`),
  `app/jobs/confirm_order_job.rb`, `app/jobs/initiate_refund_job.rb`,
  `app/views/orders/checkout.html.erb`, new `app/javascript/controllers/stripe_checkout_controller.js`
- New migrations: gateway/currency/gateway_reference on `orders`; gateway/gateway_event_id/
  gateway_payment_id on `payment_events`; gateway/gateway_refund_id on `refunds`; `prices_minor`
  on `ticket_types`; new `gateway_customers`/`payment_methods` tables (deferred, §6/§8).
