# DQOR Tickets — Codebase Map & Gap Analysis

## Stack
Rails 8.1 / Ruby 4.0.6 / **Postgres** (README's "SQLite" is stale). Solid Queue/Cache/Cable (DB-backed). Propshaft + importmap + Turbo + Stimulus (no Node build). Avo admin. Razorpay payments. RQRCode QR. Ferrum+Chromium PDF. Active Storage → Cloudflare R2. Sentry. Docker on Render (singapore). Cloudflare SMTP. RSpec + FactoryBot + Capybara/Cuprite + WebMock.

## Models (app/models)
- **Order** (central aggregate): code (unique 8-char), status enum {pending,paid,expired,canceled}, buyer_name/email/phone, total_paise, coupon_id, razorpay_order_id (unique), expires_at, gstin, gst_legal_name, billing_state_code, metadata(json). has_many tickets/payment_events/refunds/invoices (restrict_with_exception). Scopes reserving_inventory/overdue/reconcilable. Methods: mark_paid!, create_razorpay_order! (comp path if <100 paise), reconcile_payment!, refund_tickets!, confirm_from_razorpay_if_stalled!, orders_csv/attendees_csv, issue_comps!.
- **Ticket**: order_id, ticket_type_id, price_paise, secret (secure_token), claim_token (secure_token), attendee_name/email, assigned_at, canceled_at, checked_in_at (json date→ts multi-day), tshirt_size, dietary_preference, childcare_needed. has_one_attached :pdf. assign!/check_in!/request_details!. scope awaiting_details.
- **TicketType**: name, slug (unique), price_paise, capacity (nil=unlimited), min/max_per_order, sales_start/end_at, hidden, active, position, requires_conference_pass. available_quantity, purchasable?, **conference_pass? = slug.start_with?("conference-pass-")** (hardcoded).
- **Coupon**: code, percent|discount_paise (XOR), max_uses, uses_count, ticket_type_id (optional scope), valid_from/until, active. discount_for.
- **Invoice** (GST + credit notes): order_id, number (unique), issued_on, kind {invoice,credit_note}, refers_to_id, buyer_snapshot(json), line_items(json). **Immutable** (before_destroy raises). has_one_attached :pdf. issue_for! (idempotent), FY numbering, **DQOR/ & DQOR-CN/ prefixes hardcoded**, line_item_snapshot uses Gst.breakdown.
- **Refund**: order_id, amount_paise, status {pending,initiated,processed,failed}, razorpay_refund_id, credit_note_number, ticket_ids(json). process! cancels tickets + issues credit note.
- **PaymentEvent** (immutable audit log): order_id, razorpay_event_id (unique), razorpay_payment_id, kind, level, mode (test/live from key prefix), amount_paise, raw(json). record_webhook! idempotent.
- **Auth**: **AdminUser** (has_secure_password) + **Session** + **Current** — ONLY admin auth (gates Avo). **No attendee/user accounts.**

## Domain services
- **Orders::Checkout**: single txn, row-locks TicketTypes, validates selection/availability/min-max/**MAX_ITEM_QUANTITY=1000**, validate_conference_pass! (slug-based gating), applies coupon, creates Order+Tickets, 30-min hold. Errors SoldOut/InvalidSelection/ConferencePassRequired.
- **Gst.breakdown(price_paise, state_code:, gstin:)**: 18% inclusive; **CGST/SGST when state_code=="27" (Maharashtra hardcoded) else IGST**.
- **PdfRenderer**: Ferrum/Chromium renders pdfs/#{template} → PDF (invoice A4, ticket A5). 3 retries.

## Routes/Controllers
root→tickets#index; mount_avo /avo; checkin; checkout_preview; orders (create/show by code); tickets/find|access|mine→ticket_access (magic-link, MessageVerifier, session by email); orders/:code/tickets/:id/assign + claim/:claim_token→ticket_assignments; payments/callback; webhooks/razorpay; session; passwords; /up. Public controllers use allow_unauthenticated_access. **CheckinsController::EVENT_DATES hardcoded Oct 8–11 2026.**

## Avo admin
Resources: Order/Ticket/TicketType/Coupon/Invoice/Refund/PaymentEvent (some readonly). Actions: RefundTickets, ResendConfirmation, EmailOrderLink, ExportOrdersCsv, ExportAttendeesCsv, IssueCompTickets, RequestAttendeeDetails. **authorization_client=nil → every admin sees everything, no org scoping/roles.**

## Payments (Razorpay)
1. Checkout → pending Order+Tickets (30-min hold) → Razorpay::Order.create(currency:"INR") → order_created event. <100 paise → comp.
2. Browser callback (PaymentsController#callback): verify signature, record callback_verified (fallback, not authoritative).
3. **Webhook (Webhooks::RazorpayController) authoritative**: verify raw-body signature, dedupe on X-Razorpay-Event-Id. order.paid/payment.captured→ConfirmOrderJob; refund.processed→ProcessRefundJob.
4. Reconciliation: ReconcilePaymentsJob (5-min) + confirm_from_razorpay_if_stalled!.
5. Refunds: refund_tickets!→InitiateRefundJob (idempotency header)→webhook→ProcessRefundJob (cancel tickets + credit note + email).

## Jobs / schedule
ApplicationJob Retryable (retry_on TRANSIENT_ERRORS x5). Jobs: ConfirmOrder, DeliverOrderConfirmation, GenerateOrderDocuments, ExpireOrders, ReconcilePayments, InitiateRefund, ProcessRefund, WeeklyAssignmentReminders, MailDelivery. recurring.yml (prod): expire_orders & reconcile_payments every 5 min, clear finished hourly, weekly_assignment_reminders `0 9 * * 1 Asia/Kolkata`.

## Storage/PDF/QR/GST
Active Storage → R2 (S3, region auto, force_path_style). PDFs via Ferrum (invoice.html.erb A4, ticket.html.erb A5). QR = RQRCode from ticket.secret; check-in scanner html5-qrcode. GST: Gst.breakdown 18% inclusive; invoice template ENV SELLER_NAME/ADDRESS/GSTIN/SAC(998596); FY numbering DQOR/YYYY-YY/NNNN.

## Tests
RSpec + FactoryBot; factories admin_user/ticket_type/coupon/order(+:paid)/ticket/payment_event/refund/invoice. Cuprite system specs. Razorpay stubbed via WebMock. Broad model/job/request coverage.

---

# GAP ANALYSIS → generic multi-event platform

## Already generic (reusable)
Order/Ticket/TicketType/Coupon separation, inventory reservation + 30-min holds, coupon engine, min/max-per-order, sale windows. PaymentEvent audit-log + webhook-authoritative confirmation + reconciliation + idempotency (gateway-agnostic in shape). Invoice immutability + credit-note model. Active Storage abstraction, Ferrum PDF, job retry framework, magic-link + claim-token no-account attendee access.

## Single-tenant / hardcoded
1. **No Event/Organizer model** — no event_id/organizer_id FK anywhere; flat global namespace. **Biggest gap.**
2. **Branding/copy hardcoded**: "Deccan Queen on Rails"/"DQOR"/"Pune JN" in mailer subjects, PDF templates, invoice prefixes, ticket filenames.
3. **Event dates hardcoded**: CheckinsController::EVENT_DATES; ticket PDF date labels by slug.
4. **Conference-pass gating hardcoded to slug conventions** (conference_pass?, LIKE 'conference-pass-%', complimentary-pass).
5. **GST hardcoded India/Maharashtra**: 18%, state "27" home, single seller ENV, INR-only, DQOR/ sequences.
6. **Single gateway**: Razorpay hardwired into models/controllers/jobs; razorpay_* columns on core tables (not normalized); one global key pair.
7. **Single admin realm, no authorization**: one AdminUser pool, Avo authorization_client=nil.
8. Global config via ENV, not per-event/organizer.

## Foundational changes needed
1. **Tenancy**: Organizer (billing entity: legal name, GSTIN, address, SAC, tax profile, payout creds) → Event (name, slug, dates, tz, venue, branding, currency). Add event_id/organizer_id FK to TicketType/Coupon/Order/Ticket/Invoice/Refund/PaymentEvent; scope queries/inventory/uniqueness (order codes, invoice sequences) per tenant.
2. **First-class Attendee/User accounts** (alongside magic-link/claim): see all tickets across events, transfer, profile. Separate realm from AdminUser.
3. **Payment gateway abstraction**: PaymentGateway interface (create order, verify callback/webhook, refund) w/ Razorpay first adapter; normalized Payment/GatewayCharge record (polymorphic provider + provider_ref); per-organizer creds + mode.
4. **Configurable tax/invoicing**: per-organizer tax profile (rate, inclusive/exclusive, jurisdiction, currency, invoice prefix+sequence, SAC/HSN). Data-driven PDF templates (branding/dates from Event).
5. **Sessions/agenda domain** (net-new): Session/Track/Speaker/Room + scheduling + per-session capacity + attendee agenda. De-hardcode check-in from Event dates.
6. **Admin authorization + org scoping**: Avo policies, roles (super-admin vs organizer-admin), scope resources/dashboard/CSV/refunds to organizer's events.
7. **De-hardcode branding/rules**: conference-pass gating via explicit config/association (prerequisite_ticket_type) not slug prefixes; all copy/dates into Event fields + i18n.
