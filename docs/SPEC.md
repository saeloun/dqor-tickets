# Spec: dqor-tickets — self-hosted ticketing for Deccan Queen on Rails 2026

## Context

Deccan Queen on Rails (Pune, Oct 8–11, 2026) currently has no ticketing — the site's Tickets section is hidden ("Coming soon") and signups go to a FlowForm waitlist. Attendee interest is live now (applications opened July 2026). Selling via KonfHub/Townscript costs 2–3.75% + GST per ticket and gates GST tax invoices behind paid tiers; self-hosting on the organizers' own Razorpay account costs only the payment MDR (~2% + GST, UPI often less) with T+2 settlement and full control of branding and attendee data. The app will be open-sourced (`saeloun/dqor-tickets`, public, MIT) as a reusable single-event Rails ticketing reference.

Design constraint: **minimum code, OSS quality**. Lean on Rails 8 defaults, Avo for admin, razorpay-ruby, prawn. No multi-tenancy, no payout engine, no application/approval workflows.

## Current State (verified 2026-07-19)

- deccanqueenonrails.com is a static site (hidden `#tickets` section with three products already designed: Conference Pass Oct 8–9, Rails Girls Pass Oct 10 free/application-only, Explore Pune Day Add-on Oct 11 "requires conference pass, limited spots"). Waitlist posts to flowform.to. Site 403s non-browser user agents.
- Full design tokens captured (scratchpad/dqor-site/): ruby `hsl(348,70%,35%)` primary, gold/gold-light, saffron, warm cream background, complete dark-mode set, Playfair Display + Inter + Noto Sans Devanagari, shadow scale. `js/theme.js` implements the light/dark toggle.
- Razorpay: Orders API + checkout.js; signature = HMAC_SHA256(`order_id|payment_id`, key_secret); webhooks signed with separate secret over raw body, retried 24h with exponential backoff (dedupe on `x-razorpay-event-id`); Invoices API is **non-GST only** → we generate our own GST invoice PDFs. razorpay-ruby 3.2.4. `pay` gem has no Razorpay support.
- Prior art: pretix (order lifecycle, quota-holds, append-only invoices), OSEM (Rails file shape), Tito (orders-vs-tickets model). Research notes in scratchpad/research/.

## Products & Pricing (from organizer's revenue sheet, 2026-07-19)

| Seed | Price (₹) | Cap | Notes |
|---|---|---|---|
| Conference Pass — Early Bird | 3,500 | 30 | Oct 8–9 |
| Conference Pass — Regular | 4,000 | 140 | 120 open + 20 reserved for discount codes |
| Conference Pass — Late Bird | 5,000 | 30 | |
| Explore Pune Day Add-on | 2,000 (default, approved 2026-07-19, admin-editable) | 50 (default, admin-editable) | Requires a Conference Pass in the same order or an existing paid order |
| Coupon `pool` | ₹500 off Regular → ₹3,500 | 20 uses | Matches sheet's "Discount Code: 20 @ ₹3,500" row |

Total conference inventory: 200 (30+140+30). **Displayed prices are GST-inclusive** (approved 2026-07-19: ₹3,500 is what the buyer pays; invoice shows base + 18% GST broken out). All prices/caps/windows admin-editable in Avo.

## Proposed Change

New Rails 8 app `saeloun/dqor-tickets`, PostgreSQL, deployed on Render at `tickets.deccanqueenonrails.com`. Public storefront (one page, themed with the site's exact tokens) → checkout (buyer + per-attendee details, optional GSTIN) → Razorpay checkout.js → webhook-confirmed order → email with GST invoice PDF + per-ticket QR PDFs → Avo admin for everything else.

### Architecture

- **Stack** (revised 2026-07-19): Rails 8.1.x, Ruby 4.0.x, **SQLite** (app + Solid Queue/Cache/Cable, WAL, immediate transactions — ONCE/Writebook shape, one server, no other resources), Propshaft + importmap + plain CSS (site tokens; no Node build), Hotwire (Turbo for checkout status polling).
- **PDFs**: ferrum + Chromium (in Dockerfile) rendering HTML/CSS templates with the brand tokens; generated at confirmation time and stored in Cloudflare R2 via Active Storage (private bucket, signed URLs — the R2 section stands). Email attaches the generated PDFs.
- **Locking**: SQLite single-writer immediate transactions replace SELECT FOR UPDATE in checkout.
- **Gems** (the whole list): razorpay, avo, prawn + prawn-qrcode (invoice + ticket PDFs), rqrcode, friendly_id NOT needed (fixed slugs), devise NOT needed — admin auth via Rails 8 built-in `has_secure_password` + session (one AdminUser model, Avo authenticates against it). rspec-rails + capybara + webmock for tests. rubocop-rails-omakase. That's it — no aasm (plain enum + guards), no money-rails (integer paise + helper), no cancancan (single admin role).
- **No JS build**: checkout.js loaded from Razorpay CDN; one Stimulus controller for the checkout modal + countdown.

### Domain model

```
TicketType: name, slug, description, price_paise (int), capacity (int, null=∞),
            sales_start_at/sales_end_at (nullable), min/max_per_order,
            hidden (bool, comp/access-code types), requires_conference_pass (bool),
            position, active
Order:      code (8 chars, charset ABCDEFGHJKLMNPQRSTUVWXYZ379, unique),
            status enum {pending:0, paid:1, expired:2, canceled:3},
            email, buyer_name, buyer_phone,
            gstin (nullable), gst_legal_name, billing_state_code (2-digit),
            total_paise, expires_at, razorpay_order_id (uniq),
            coupon_id (nullable), metadata jsonb
Ticket:     order_id, ticket_type_id, price_paise (snapshot),
            attendee_name, attendee_email, tshirt_size, dietary_preference,
            secret (SecureRandom.base58(24), uniq — QR payload),
            checked_in_at (per-day: checkin jsonb {"2026-10-08": ts, ...}),
            canceled_at
PaymentEvent: razorpay_event_id (uniq index — webhook dedupe),
            razorpay_payment_id (uniq), order_id, kind, amount_paise, raw jsonb
Refund:     order_id, razorpay_refund_id, amount_paise, status, credit_note_number
Invoice:    order_id, number (uniq, "DQOR/2026-27/0001" — FY sequence; credit notes
            own prefix "DQOR-CN/"), issued_on, buyer + line-item snapshot jsonb,
            kind {invoice, credit_note}, refers_to_id (credit note → original);
            unique partial index on order_id where kind='invoice' (one tax invoice
            per order, many credit notes allowed); before_destroy :raise
Coupon:     code (uniq, case-insensitive), discount_paise OR percent,
            max_uses, uses_count, ticket_type scope, valid window, active
AdminUser:  email, password_digest
```

### Order lifecycle (pretix recipe)

1. `POST /orders`: transaction → `TicketType.where(id: ids).order(:id).lock` → availability = capacity − tickets in (paid ∪ unexpired-pending) orders → reject if short → create Order `pending`, `expires_at = 30.minutes.from_now`, tickets with price snapshots → `Razorpay::Order.create(amount: total_paise, currency: "INR", receipt: code)`.
2. Checkout page: countdown timer, checkout.js modal with `order_id` + prefill.
3. Handler POSTs the 3 params → `verify_payment_signature` → show "confirming" state (Turbo poll).
4. **Webhook `order.paid` is authoritative**: verify signature on raw body → insert PaymentEvent (unique `razorpay_event_id`; duplicate → 200 no-op) → job: order `with_lock` → already paid? no-op : mark paid, generate invoice (FY-sequence inside this transaction, `RecordNotUnique` retry), enqueue confirmation email with invoice PDF + ticket PDFs (QR = ticket.secret).
5. `payment.failed` → record event, surface retry UI. Expiry job (Solid Queue recurring, every 5 min) flips overdue pending → expired (frees inventory). Razorpay auto-refunds late-captured payments on expired orders — webhook path re-checks availability and can revive an expired order if stock remains, else admin refunds.
6. Refund: always admin-initiated in Avo with explicit ticket selection — refund amount = sum of selected tickets' snapshot prices → `payment.refund` (partial/full) → `refund.processed` webhook (matched on `razorpay_refund_id`) → cancel selected tickets, issue credit note for exactly those line items, email buyer. Out-of-order/duplicate refund webhooks are no-ops via Refund status guard.

### Decision log (gate findings resolved)

- **Tier precedence**: a tier is purchasable iff `active` AND inside its date window (when set) AND not sold out. All tiers render; others show "coming soon"/"sold out". No automatic cascade — Early Bird selling out doesn't toggle anything, Regular is already active. Manual kill = `active:false`.
- **Coupon counting**: discount validated + snapshotted into the order at creation; `uses_count` incremented only inside the payment-confirm transaction. Two pending orders racing the last use are both honored (bounded oversubscription ≤ pending window, acceptable at 20-coupon scale).
- **GST rounding**: per line, taxable = `(price_paise / 1.18).round` (paise), tax = price − taxable, split half CGST/half SGST (odd paise → CGST gets the extra); invoice totals = sum of line values so the PDF always reconciles.
- **Browser callback**: `verify_payment_signature` success records a PaymentEvent (`kind: callback_verified`) but never marks paid; status page polls, and after 30 s without webhook confirmation the server fetches `Razorpay::Order` payments once as fallback confirmation (same idempotent confirm path).
- **Add-on eligibility**: Explore Pune Day is purchasable (a) in the same order as a Conference Pass, or (b) standalone by entering an existing paid order's code + buyer email — both values are private to the buyer's inbox; codes are 8 chars over a 27-char alphabet (~10^11 space), rate-limited lookup, and the lookup only confirms eligibility.
- **Admin bootstrap**: Rails 8 authentication generator (bcrypt session auth, rate-limited); first AdminUser created by `db/seeds.rb` from `ADMIN_EMAIL`/`ADMIN_PASSWORD` env (no signup route). Avo hooks into this session.
- **PDF lifecycle**: invoice + ticket PDFs generated once at confirm time, attached via Active Storage → R2; `/orders/:code` serves them through authenticated-by-code redirects to signed R2 URLs (short expiry).

### GST invoices (own PDFs, prawn)

Supplier: Saeloun's legal name/GSTIN/address via ENV/credentials. SAC 998596, 18%. Buyer state 27 (Maharashtra) → CGST 9% + SGST 9%; else IGST 18%. No GSTIN → B2C invoice, same math, place of supply = Maharashtra. Number sequence per Indian FY. Line items snapshot at creation; credit notes for refunds. README carries a "verify with your CA" note (s.12(6) vs 12(7) place-of-supply choice).

### Storefront & theming

- `/` tickets page mirroring the site's hidden tickets-section design: ticket cards (ruby featured card, gold/saffron accents), sold-out/coming-soon states, light/dark theme (same `theme.js` behavior), Playfair Display headings / Inter body / Noto Sans Devanagari accents ("डेक्कन क्वीन"). CSS custom properties copied verbatim from global.css.
- Checkout: buyer details, per-ticket attendee forms (name, email, t-shirt, dietary), optional GSTIN block, coupon field, Explore Pune Day cross-sell (only addable with a Conference Pass in order or a paid order's email+code).
- Order status page `/orders/:code` (re-download invoice + tickets).
- Legal pages: /terms, /privacy, /refund-policy (static, required for Razorpay KYC).

### Admin (Avo, free tier)

Resources: TicketType, Order, Ticket, Coupon, Invoice, Refund, PaymentEvent (read-only). Custom Avo actions: **Refund order** (amount input), **Issue comped tickets** (pick type, emails → creates paid ₹0 order, sends tickets), **Resend confirmation**, **Export CSV** (orders/attendees). Avo dashboard cards: revenue, sold-by-type vs caps, sales-over-time. Check-in: one custom controller `/checkin` (admin-authed, mobile web): camera QR scan (html5-qrcode vendored) + name search; per-day check-in with duplicate-scan guard.

### Payment Links (no extra code)

Sponsor/bulk invoicing handled via Razorpay dashboard Payment Links + admin comp issuance — documented in README, not built.

### Deployment & infrastructure

- **Render**: `render.yaml` blueprint — web service (Puma), Solid Queue via Puma plugin (single service — no separate worker; conference scale), PostgreSQL. Health check `/up`. Test-mode keys first; webhook URL configured for test + live separately.
- **Cloudflare**: DNS for `tickets.deccanqueenonrails.com` (CNAME → Render, proxied), same zone as the main site.
- **Cloudflare R2** (S3-compatible) via Active Storage `s3` adapter: stores generated invoice PDFs and ticket PDFs (immutable archive — invoices must survive redeploys); private bucket, served through signed URLs/Rails redirects, never public.
- Env: `RAZORPAY_KEY_ID/KEY_SECRET/WEBHOOK_SECRET`, `SELLER_*` (GSTIN etc.), `SMTP_*` (Resend/Postmark), `R2_ACCOUNT_ID/ACCESS_KEY_ID/SECRET_ACCESS_KEY/BUCKET`, `RAILS_MASTER_KEY`.

## Acceptance Criteria

1. Buyer purchases 2× Early Bird with test UPI `success@razorpay`; order flips paid via webhook (not the browser callback); email contains GST invoice PDF (correct CGST/SGST split, sequential number) and 2 ticket PDFs with distinct QR codes.
2. Signature-invalid webhook → 400; duplicate webhook delivery (same `x-razorpay-event-id`) → 200 and exactly one invoice/email.
3. Concurrency: 2 parallel checkouts for the last seat → exactly one pending order succeeds (request spec with threads).
4. Pending order past `expires_at` frees inventory; expired-order late payment either revives (stock available) or is flagged for refund.
5. Buyer with GSTIN `27AAAAA0000A1Z5` gets CGST+SGST invoice; state 29 gets IGST; no GSTIN gets B2C invoice.
6. Coupon at max uses or expired is rejected; valid coupon prices Regular at ₹3,500 and decrements uses once per paid order (not per attempt).
7. Explore Pune Day cannot be purchased without a Conference Pass (same order or referenced paid order).
8. Avo: refund action creates Razorpay refund (test mode), credit note PDF, cancels tickets. Comp action issues ₹0 paid order with tickets.
9. Check-in: scanning a ticket QR marks Oct 8 check-in; second scan shows "already checked in at HH:MM"; canceled tickets rejected.
10. Sold-out tier shows sold-out state and next tier becomes purchasable.
11. Full RSpec suite green in CI (GitHub Actions); rubocop-rails-omakase clean.
12. Deployed on Render from `render.yaml` behind Cloudflare DNS; invoice/ticket PDFs persisted to R2 and re-downloadable from `/orders/:code` after a redeploy; storefront matches site theme in light + dark (visual check with Playwright).

## Testing Plan

| Layer | What | ~Count |
|---|---|---|
| Model | availability/locking, order code gen, coupon rules, invoice numbering + FY rollover, GST math (all 3 buyer cases), state guards | ~30 |
| Request | checkout create, webhook (valid/invalid sig, dupe event, out-of-order events), order status, checkin endpoint, admin auth | ~25 |
| Jobs/Mailers | expiry job, confirmation email w/ attachments, refund flow | ~8 |
| System (capybara) | happy-path purchase w/ stubbed Razorpay, sold-out flow, coupon | ~5 |

Webhook fixtures signed with the real HMAC algorithm; Razorpay HTTP stubbed with WebMock. Live test-mode E2E once via tunnel before launch (manual checklist in README).

## Rollback Plan

Render rollback to previous deploy; DB migrations additive-only pre-launch. Payments live in Razorpay dashboard regardless — worst case, refund from dashboard and re-issue comps. Feature kill-switch: `TicketType.active=false` hides sales instantly.

## Effort (CC+Codex agent time)

Scaffold+schema ~1h, checkout+Razorpay+webhooks ~3h, invoices/GST/PDF/email ~3h, Avo+checkin ~2h, theming ~2h, tests ~4h, Render/R2/CF+CI ~2h ⇒ ~2–3 focused build days including verification passes (human-team equivalent: ~3–4 weeks).

## Out of Scope (v1)

Rails Girls applications & approval flows, waitlist auto-offers, self-serve transfers/refunds, attendee messaging campaigns, sponsor portal, multi-currency, e-invoicing (AATO < ₹5cr assumed), WhatsApp delivery, badge printing, multi-event support.

## Open items for organizer

- Confirm Explore Pune Day price (assumed ₹2,000) and cap (assumed 50).
- Confirm prices are GST-inclusive (assumed yes).
- Razorpay KYC + live keys; GSTIN/legal entity details for invoice header; CA sign-off on SAC/place-of-supply; SMTP provider choice; DNS record for tickets subdomain.
