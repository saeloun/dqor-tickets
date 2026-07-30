# Platform Plan — Evolving dqor-tickets into an Open-Source, India-First Event Platform

Status: **Authoritative architecture + roadmap.** Synthesized 2026-07-29 from six research documents
(codebase map, OSS platform survey, India payments/compliance, multi-gateway design, competitor UX,
integrations/networking). An engineer should be able to start Phase 2 from this document alone.

---

## 1. Vision & scope

### 1.1 What we are building

A **generic, open-source, India-first event platform**: Luma-grade attendee UX (one-click RSVP,
beautiful event pages, guest-list social proof) with Townscript-grade commerce breadth (tiered
ticketing, coupons, GST invoicing, UPI-first checkout, organizer payouts) plus a **conference
module** (sessions, speakers, sponsors, personal agendas, networking) that no OSS platform combines
today. Pilot tenants: **Deccan Queen on Rails (DQOR)** — the existing production conference — and
**RubyConf India-class events**, but every feature must be configurable per organizer, never
hardcoded to either.

The OSS landscape validates the gap (research doc 01): Pretix has the best inventory model but no
conference agenda; Hi.Events has the best waitlist/payout modeling but zero sessions/speakers;
Open Event Server has the deepest conference model but weak commerce; nobody has Luma's UX or
India-first GST/UPI/Route compliance. We synthesize: **pretix's Quota + SubEvent**, **Hi.Events'
waitlist + Connect-style payouts (adapted to Razorpay Route)**, **Open Event Server's
Session/Speaker/Track/Sponsor**, **Alf.io's integer-minor-units money pipeline and SponsorScan**,
and **Luma's RSVP-before-pay flow and design language**.

### 1.2 What already exists (and is kept)

dqor-tickets is a production Rails 8.1 / Postgres / Hotwire app with a genuinely reusable core:
Order/Ticket/TicketType/Coupon separation, row-locked inventory with 30-minute holds,
webhook-authoritative payment confirmation with reconciliation fallbacks, immutable
PaymentEvent audit log, immutable GST Invoice + credit-note model, Ferrum PDF rendering, R2
storage, Solid Queue jobs, magic-link/claim-token attendee access, and broad RSpec coverage.
We evolve this app in place — **no rewrite, no second codebase**.

### 1.3 Non-goals (explicit, per product owner)

| Non-goal | Why / what we do instead |
|---|---|
| **NO CFP / talk-submission workflow** | Sessions are entered by organizers as a published agenda. The `Session` model reserves a `state` column shaped like OSEM/Open Event Server's lifecycle so CFP can be added later without a migration storm, but no submission UI, review UI, or reviewer roles are built. |
| **NO custom email-template builder** | Email sequences are predefined trigger points with merge-field bodies (OSEM `EmailSettings` pattern), editable subject/body text only. No drag-drop designer, no MJML, no per-organizer HTML templates. |
| No becoming an RBI Payment Aggregator | We ride Razorpay's PA licence via Route. Never collect buyer funds into our own bank account (research doc 02 §3.1 — this is a legal constraint, not a preference). |
| No seat maps / reserved seating | Eventbrite-class venue seating is out of scope indefinitely. |
| No AI matchmaking | Networking v1 is opt-in directory + tag filtering + connection requests. Transparent, no black box. |
| No federation (ActivityPub) | Mobilizon's Actor model is elegant but overkill for a commerce platform. |
| ~~No native mobile apps~~ **→ now in scope (§8, P11)** | Native iOS/Android via **Hotwire Native** (one codebase wrapping the web app) + NFC/camera/push bridges. Web stays the source of truth; native adds capability where it matters. Check-in scanner remains html5-qrcode on web and gains native NFC on mobile. |

---

## 2. Architecture decisions

Each decision records the choice, the rationale, and the tradeoff considered and rejected.

### AD-1: Multi-tenancy — row-scoped FKs under Account → Organizer → Team → Event

**Decision.** Four-level hierarchy, all in one Postgres schema, scoped by foreign keys:

```
Account            # platform-level tenant: one signup, one billing relationship
  └── Organizer    # a brand / legal entity: GSTIN, PAN, Route linked account, invoice series
        ├── Membership (user_id, role)   # RBAC within the organizer
        └── Event                        # one edition: dates, venue, currency, branding
              └── EventOccurrence        # optional: one date within a series (pretix SubEvent)
```

- All commerce tables (`ticket_types`, `coupons`, `orders`, `tickets`, `invoices`, `refunds`,
  `payment_events`, plus every net-new table) gain an `event_id` FK. Tables that are inherently
  organizer-level (`invoice_sequences`, `payout_accounts`, `memberships`) get `organizer_id`.
  `orders` carries **both** `event_id` and a denormalized `organizer_id` for payout/report queries.
- **Row scoping, NOT schema-per-tenant, NOT the `apartment` gem.** Rationale: (a) cross-tenant
  queries are core product features — the Discover page, a user's "My Events" across organizers,
  platform-level TCS/TDS reporting all read across tenants; (b) schema-per-tenant multiplies
  migration time by tenant count and is hostile to Solid Queue/Cache which share the DB;
  (c) every surviving OSS platform surveyed (pretix, Hi.Events, Alf.io, Open Event Server) uses
  row scoping. Tradeoff accepted: a missing `where(event_id:)` is a data-leak bug rather than a
  connection-level impossibility. Mitigation: `Current.event` / `Current.organizer` attributes +
  default scoping in controllers + Avo policy scoping + a request spec per resource asserting
  cross-tenant isolation.
- **Why the Account level at all** (vs. flat Organizer → Event like pretix): Hi.Events' two-tier
  split matches the India market — event-management agencies run many client brands under one
  billing relationship, and the platform's own commission invoicing hangs off Account. It costs
  one table now and is very painful to retrofit later. In v1, Account:Organizer is almost always
  1:1 and the UI can hide the distinction.
- **RBAC**: `Membership(organizer_id, user_id, role)` with roles
  `owner | admin | editor | finance | checkin_operator | viewer`. This is pretix's Team model
  flattened to one row per user (Open Event Server style) — a full Team entity (invite a named
  group) is deferred until a real customer needs it; the `memberships` table shape doesn't change
  either way. Check-in operators get a deliberately tiny surface (scan + guest list only),
  mirroring Luma's "check-in staff" role.

**Tenant resolution.**

| Surface | How the tenant is resolved |
|---|---|
| Public event pages | URL: `/:organizer_slug/:event_slug` (Luma-style `/c/rubyconf/2026`). Slug lookup sets `Current.organizer` + `Current.event`. Organizer slugs globally unique; event slugs unique per organizer. |
| Custom domains (later) | `Host → organizer` lookup table checked in a `before_action`; falls through to path-based routing. Not built until an organizer asks. |
| Organizer admin (Avo + custom) | From the signed-in user's memberships. If >1 organizer, an explicit organizer switcher persisted in session; `Current.organizer` set in a base controller `before_action`, and **every** Avo resource scoped through it (AD-7). |
| Webhooks / jobs | Never from request context. Jobs receive IDs; webhook processing derives the order (and thus event/organizer) from `(gateway, gateway_reference)`. |
| Uniqueness scopes | `orders.code` unique per event; invoice numbers unique per `(organizer, series, fiscal_year)`; `ticket_types.slug` unique per event. Existing global unique indexes are migrated to composite ones in Phase 2. |

### AD-2: Payment abstraction — `Payments::Gateway` port + adapters + `Payments::Router`

**Decision.** Ports-and-adapters exactly as specified in research doc 03 (which was written against
the live codebase and is adopted wholesale):

- **Port** `Payments::Gateway` (`app/models/payments/gateway.rb`): `create_intent`,
  `verify_client_callback`, `capture`, `refund`, `verify_webhook`, `fetch_captured_payment`, plus
  an optional tokenization surface (`create_customer` / `start_tokenization` /
  `charge_saved_method`). Adapters return value objects (`Payments::Intent`, `Payments::Result`,
  `Payments::WebhookEvent`) — no SDK object ever crosses the boundary; `Order`, jobs, and
  controllers never `require "razorpay"` again.
- **Adapters**: `RazorpayGateway` (a mechanical *extraction* of today's logic — the hardest PR to
  review because any behavior diff is a bug), `StripeGateway` (Payment Element, `return_url`,
  manual capture for approval/waitlist holds), `PayuGateway` (hash-signed form POST; deferred
  until a second India rail is a real business need — the port is shaped for it).
- **Router** `Payments::Router.resolve(request:, override_param:)`: geo via the **`CF-IPCountry`**
  header (Cloudflare already fronts the app), `Accept-Language` region as weak fallback, default
  `"IN"`. `GATEWAY_BY_COUNTRY = {"IN" => :razorpay}`, `DEFAULT_GATEWAY = :stripe` (once Stripe is
  live), one reversible user-facing override link ("Pay in USD instead →" / `?pay_with=`), cookie-
  persisted. **The decision is resolved exactly once, at order creation, and stamped immutably on
  the order** (`gateway`, `currency`, `country` columns) — every downstream path (webhooks,
  reconciliation, refunds, invoicing) reads `order.gateway`, never re-detects. This mirrors how
  `total_paise` is frozen at creation, and for the same reason: a buyer's IP can change
  mid-session; an order's payment rail must not.
- **Normalized event log**: `payment_events` widened to `(gateway, gateway_event_id,
  gateway_payment_id)` with a unique index on `(gateway, gateway_event_id)` — the existing
  `insert_all!` + `rescue RecordNotUnique` idempotency pattern is already gateway-agnostic in
  spirit and only widens. One webhook endpoint `POST /webhooks/gateways/:gateway` +
  `Payments::WebhookProcessor` switching on neutral `KINDS`
  (`:payment_captured`, `:refund_processed`, …), replacing per-gateway controllers.
- **Outbound idempotency** per gateway: Razorpay `receipt`=order.code + `X-Refund-Idempotency`;
  Stripe `idempotency_key` request option; PayU deterministic `txnid` backed by the DB unique
  index on `orders(gateway, gateway_reference)`.
- **Saved cards: token-only, per RBI CoFT.** No column in the schema can hold a PAN — structurally
  impossible, not policy-discouraged. `gateway_customers(gateway, email, gateway_customer_id)` +
  `payment_methods(token_reference, card_last4, consent_captured_at NOT NULL, …)`. Tokens are
  vault-scoped and never portable across gateways (a returning Razorpay buyer routed to Stripe
  simply re-tokenizes). Deferred feature — schema ships when repeat-purchase is prioritized, and
  frankly may never be worth it for a 1–2 orders/year product.

**Tradeoff considered**: a `Payment` gem (ActiveMerchant / Pay). Rejected: ActiveMerchant has no
UPI/Razorpay-webhook-first model; `pay` gem is Stripe/Paddle-shaped and would fight the existing
PaymentEvent/reconciliation machinery, which is battle-tested in production. Our port is ~6 methods;
owning it is cheaper than adapting around a gem's assumptions.

**Multi-currency**: `ticket_types.prices_minor` jsonb (`{"inr" => 500000, "usd" => 6000}`),
admin-managed prices, **no live FX in the checkout path**. `price_paise` remains the INR source of
truth during transition. Renaming `total_paise → total_minor` is a follow-up mechanical PR that
must not share a diff with adapter work.

### AD-3: Payouts & the legal supplier model — Razorpay Route, organizer as GST supplier

**Decision.** The platform is legally a **marketplace/e-commerce operator (ECO)**, and its
money-collection function is regulated payment aggregation. Therefore (research doc 02, all of it):

1. **The platform never self-aggregates.** Buyer funds land in Razorpay's RBI-mandated escrow
   against the platform's merchant ID. **Razorpay Route** creates one **Linked Account per
   organizer** (own KYC: legal name, entity type, PAN, bank account in the entity's name —
   penny-drop validated at onboarding). Every captured payment generates Route **Transfers**:
   organizer's share to their linked account, platform commission retained — attribution stays at
   the individual-transaction level. Configurable settlement hold (T+2…T+7) per organizer as a
   chargeback/refund buffer for unproven organizers.
2. **RazorpayX Payouts** for what Route can't express: sponsorship disbursements not tied to a
   ticket transaction, refund top-ups, ad-hoc vendor/speaker payments. Fund-account validation
   APIs used before first payout.
3. **The organizer is the legal GST supplier** of the admission service (SAC 998596 @ 18%). The
   organizer's name/GSTIN/address go on every buyer invoice. The **platform separately invoices
   the organizer B2B** for its commission (SAC 998599 @ 18%). Conference admission is *not* a
   Section 9(5) deemed-supplier category, so the platform's own GST exposure is limited to TCS +
   its commission invoice — a materially lighter load than a cab/food marketplace.
4. **Withholding at settlement, before crediting the organizer**: **Section 194-O TDS at 0.1%**
   of gross (5% if no PAN; resident individual/HUF ≤₹5L/yr exempt *with* PAN furnished) and
   **Section 52 GST TCS at 0.5%** of net taxable value. Both are modeled as explicit lines on the
   `Payout` ledger. Rates live in config (`Rails.application.config.x.compliance`), never
   hardcoded — both have already been cut once since 2024.
5. **Settlement waterfall is a first-class ledger** shown to organizers per order:
   gross → platform fee (+GST) → TCS → TDS → net payout, plus "GST you still owe separately."
   Research doc 02 §5.3 is the reference computation; building this transparently is the
   difference between a support-ticket firehose and none.
6. **Escape hatch preserved**: DQOR itself (platform and organizer are the same legal entity in
   the pilot) can run in a **`direct` payout mode** — organizer uses their own Razorpay keys, no
   Route split, no TDS/TCS (you can't withhold from yourself). `organizers.payout_mode` enum
   (`direct | route`) makes marketplace mechanics opt-in per organizer, which also lets us ship
   tenancy phases long before Route onboarding is legally reviewed.

**Tradeoff considered**: collecting into our own account and disbursing via bank transfer
("we'll get to compliance later"). Rejected outright — it is a Payment and Settlement Systems Act
violation, not a technical debt item.

### AD-4: Tax & invoicing — per-organizer tax profile, venue-state place of supply, data-driven PDFs

**Decision.**

- **`TaxProfile` per organizer** (overridable per event): `country`, `gstin`,
  `legal_name`, `registered_state_code`, `sac_code` (default `"998596"`), `tax_rate_bp` (default
  1800 basis points), `tax_inclusive` (default true — Indian B2C convention: show ₹X
  all-inclusive, back-calculate taxable value = X ÷ 1.18, print the breakup), `invoice_prefix`,
  `lut_number` (nullable — for zero-rated exports, pending CA sign-off).
- **Place of supply = the venue's state** (IGST Act s.12(6)/13(5)) — **not** the buyer's state,
  not the supplier's registered address. `events.venue_state_code` is the tax anchor:
  - organizer registered in venue state → CGST + SGST of that state;
  - otherwise IGST — *and* an onboarding flag: "your GST state differs from the venue state; you
    may need Casual Taxable Person registration" (CTP is a human/CA item, §6).
  - A Delhi buyer of a Pune event still gets CGST+SGST(Maharashtra) — state this on the invoice.
  - The current `Gst.breakdown` hardcodes home state `"27"` — replaced by
    `Gst.breakdown(amount_minor, venue_state_code:, supplier_state_code:, buyer_gstin:, rate_bp:)`.
- **Rule 46 compliance**: invoices carry all 16 mandatory fields (heading, supplier legal
  name/address/GSTIN, ≤16-char consecutive per-FY serial, date, recipient details + GSTIN or
  "unregistered", **place of supply with state name+code**, SAC, description with event name/dates,
  quantity, taxable value, rate, CGST/SGST *or* IGST shown separately — never a blended "GST" line,
  signature). A deficient invoice risks ₹25k/invoice and kills the buyer's ITC.
- **Rule 50 receipt vouchers on advance**: services attract GST at receipt, so every early-bird
  sale before the event generates a **Receipt Voucher** document (`invoices.kind` gains
  `receipt_voucher`), with the final Rule 46 tax invoice issued at/before the event adjusting the
  advance. Whether DQOR continues its current issue-invoice-immediately-on-payment practice or
  moves to voucher-then-invoice is a CA sign-off item (§6); the engine supports both via a
  per-organizer `invoice_timing` setting (`immediate | voucher_then_invoice`).
- **GSTIN validation**: 15-char structure + **Luhn mod-36 check character** validated client- and
  server-side (`Gstin.valid?`); "Active" status verification against the GST portal API at
  organizer onboarding (format-valid ≠ registered).
- **Numbering**: `invoice_sequences(organizer_id, series, fiscal_year, last_number)` with
  `SELECT … FOR UPDATE` increments. Prefix from TaxProfile (`DQOR/` becomes the migrated
  organizer's configured prefix; `-CN/` credit-note series preserved). Existing issued invoices
  are never renumbered.
- **Multi-currency / export sales**: a Stripe/USD order to a non-resident buyer is very likely a
  zero-rated **export of service under LUT** — no CGST/SGST/IGST lines. `Invoice.issue_for!`
  branches on order currency/gateway; the *actual tax treatment* is a CA decision (§6) and ships
  behind a flag defaulting to "GST-invoice everything" until signed off.
- **E-invoicing (IRN)**: B2C sales need no IRN regardless of turnover. Build an opt-in IRP
  integration hook only for organizers >₹5cr turnover issuing B2B invoices to a buyer GSTIN.
  Threshold is config, not code (₹5cr → possible ₹2cr change was live at research time).
- **PDF templates fully data-driven**: branding (name, logo, colors), event dates, venue, seller
  block all render from `Event`/`Organizer`/`TaxProfile` — the ENV `SELLER_*` vars and the
  hardcoded "Deccan Queen on Rails / Pune JN" strings in `invoice.html.erb`, `ticket.html.erb`,
  mailers, and filenames are eliminated in Phase 2. Ferrum rendering pipeline unchanged.

### AD-5: Attendee identity — GitHub OAuth + magic link, linked by verified email

**Decision.**

- **New `User` model** (attendee realm) separate from `AdminUser` — the two realms never merge;
  organizer staff get `User` accounts + `Membership` rows, and `AdminUser` shrinks to
  platform-superadmin before eventually folding into `User`+role (Phase 10 cleanup, optional).
- **Auth methods**: (1) **GitHub OAuth** via OmniAuth — primary, because the pilot audience is
  Ruby developers and GitHub is their trusted identity + free avatar source (Luma itself doesn't
  offer GitHub; this is our deliberate substitution). Scopes: `read:user user:email` **only** —
  no repo, no write. (2) **Email magic link** — universal fallback, no passwords ever; reuses the
  proven MessageVerifier machinery from `ticket_access`. `identities(user_id, provider, uid)`
  table allows adding Google later without schema change.
- **Account linking by verified email**: a GitHub login whose verified email matches an existing
  magic-link account links to it (adds an identity row) rather than creating a duplicate — the
  same behavior Luma documents for Google/Apple. Unverified GitHub emails do NOT auto-link
  (takeover risk); they get a confirmation mail instead.
- **Auth is never a wall**: browsing events, and even buying tickets, work without an account
  (guest checkout keeps the existing order-code + magic-link access path). The auth prompt appears
  only on identity-requiring actions (RSVP, "My events", networking) as a modal, with post-auth
  return-to-action (stash intent in session, resume the Turbo Frame).
- **`Registration` model** with **two orthogonal state dimensions** (the single most important UX
  mechanic from Luma, research doc 04 §3.3):

  ```ruby
  Registration
    belongs_to :event, :user; belongs_to :ticket, optional: true
    enum :attendance_state, { interested: 0, going: 1, waitlisted: 2,
                              pending_approval: 3, cancelled: 4 }
    enum :payment_state,    { not_required: 0, awaiting_payment: 1, authorized: 2,
                              captured: 3, refunded: 4, released: 5 }
  ```

  - `interested` = one click, no payment intent, no capacity consumed (a bookmark + host lead
    signal Luma doesn't even have).
  - Free RSVP → `going / not_required` instantly. Paid → `going` only after capture.
  - **Approval-required paid** → `pending_approval / authorized` (Stripe manual-capture
    PaymentIntent hold; on Razorpay, where auth-hold UX is weaker, v1 approval-gated tickets take
    payment *after* approval via a payment link — `awaiting_payment` state — rather than
    pretending to hold). Host approves → capture → `going/captured`; declines → release.
  - Access state is **derived**, never stored: `going && (free || captured)` ⇒ QR ticket valid.
  - Existing `Ticket` remains the badge/QR/PDF entity; `Registration` links `user ⇄ event` and
    (when a purchase exists) points at the ticket. Guest-checkout orders have tickets without
    registrations until the buyer later creates/links an account by verified email.
- **Avatar fallback chain** (resolved once, cached by `user_id + updated_at`):
  uploaded avatar → GitHub `avatar_url` → **Gravatar** (SHA-256 of downcased email,
  `d=identicon&r=pg`) → local deterministic initials-SVG. Guest-list avatar stack uses
  `flex -space-x-2` overlapping circles with ring separation, "+N" chip, `loading="lazy"` past 8,
  and a Stimulus `onerror` swap to the initials fallback. Public guest list is host-toggleable
  per event (single switch, Luma's privacy model); `pending_approval`/`waitlisted` are excluded
  from the public stack so social proof stays honest.

**Tradeoff considered**: Devise. Rejected — the app already has a hand-rolled session/password
stack for AdminUser and a MessageVerifier flow; OmniAuth + a ~100-line magic-link controller is
less machinery than Devise + devise-passwordless + omniauthable, and keeps the no-password stance.

### AD-6: Naming collision — auth `Session` vs conference sessions

The app already has `app/models/session.rb` (admin auth sessions). The conference-talk model is
therefore named **`ProgramSession`** (table `program_sessions`) with `Track`, `Room`,
`ProgramSessionSpeaker`. This avoids a rename migration of live auth data and keeps
`has_many :sessions` unambiguous. (Renaming auth `Session → AuthSession` was considered and
rejected: it touches production session storage for zero user value.)

### AD-7: Admin — keep Avo, add authorization

Avo stays for organizer admin (it already covers Orders/Tickets/Refunds/Invoices well). Changes:
`authorization_client = :pundit` with policies scoping **every** resource through
`Current.organizer`'s events; role checks from `Membership` (finance sees payouts/invoices,
checkin_operator sees nothing in Avo — they get the dedicated scanner UI); platform superadmin
(AdminUser) retains cross-tenant access with an explicit "acting on organizer X" banner. Attendee-
and organizer-facing product surfaces (event editor, guest list, blasts, agenda builder) are
**custom Hotwire UI**, not Avo — Avo is the back-office, not the product.

---

## 3. Canonical data model

Legend: **[KEEP]** existing model, minimal change · **[SCOPE]** existing model gaining
`event_id`/`organizer_id` + refactor · **[NEW]** net-new. All money columns are **integer minor
units** (paise/cents) — never float, never decimal; every new money column is named `*_minor`
(existing `*_paise` columns are aliased then renamed in a dedicated cleanup PR). All timestamps
UTC; event display through `events.timezone`.

### 3.1 Tenancy & identity

| Entity | Key fields | Notes |
|---|---|---|
| **Account** [NEW] | name, billing_email, country, status | Platform tenant / billing root. 1:1 with Organizer in v1. |
| **Organizer** [NEW] | account_id, name, **slug** (global-unique), description, logo, support_email, default_currency ("INR"), default_timezone ("Asia/Kolkata"), payout_mode (`direct`/`route`), razorpay_linked_account_id, pan, entity_type (individual/proprietorship/company/trust/…), status | The brand + legal entity. entity_type drives 194-O exemption & sponsorship RCM logic. |
| **TaxProfile** [NEW] | organizer_id (+ optional event_id override), gstin, legal_name, registered_state_code, address fields, sac_code, tax_rate_bp, tax_inclusive, invoice_prefix, cn_prefix, invoice_timing, lut_number | AD-4. GSTIN Luhn-mod-36 validated. |
| **Membership** [NEW] | organizer_id, user_id, role enum (owner/admin/editor/finance/checkin_operator/viewer) | Unique on (organizer_id, user_id). |
| **User** [NEW] | email (citext, unique), name, avatar (ActiveStorage), github_login, timezone, preferences jsonb | Attendee realm. |
| **Identity** [NEW] | user_id, provider ("github"), uid, auth data jsonb | Unique (provider, uid). |
| **MagicLinkToken** | — | Not a table; signed MessageVerifier tokens, single-purpose, 15-min expiry (existing pattern reused). |
| **AdminUser** [KEEP] | — | Shrinks to platform superadmin. |
| **Session** [KEEP] | — | Auth sessions (admin now, users in P3). See AD-6. |

### 3.2 Events

| Entity | Key fields | Notes |
|---|---|---|
| **Event** [NEW] | organizer_id, title, **slug** (unique per organizer), status (draft/published/archived/cancelled), format (in_person/online/hybrid), starts_at, ends_at, timezone, venue_name, venue_address, **venue_state_code** (tax anchor), latitude/longitude, currency, visibility (public/unlisted/private), cover_image, theme (curated enum), brand jsonb (colors/copy for PDFs & pages), guest_list_public bool, capacity (nullable), settings jsonb | The de-hardcoding target: EVENT_DATES, PDF branding, mailer copy all read from here. |
| **EventOccurrence** [NEW, deferred to first recurring-event customer] | event_id, starts_at, ends_at, venue overrides, capacity_override, is_cancelled | pretix SubEvent / Hi.Events occurrences. Table designed now, built when needed; `tickets.event_occurrence_id` nullable FK reserved. |

### 3.3 Ticketing & inventory

| Entity | Key fields | Notes |
|---|---|---|
| **TicketType** [SCOPE] | + event_id; name, slug (unique per event), kind (paid/free/donation), min/max_per_order, sales window, hidden, active, position, requires_approval bool, **prerequisite_ticket_type_id** (nullable FK — replaces the hardcoded `slug.start_with?("conference-pass-")` gating), prices_minor jsonb, capacity (legacy, superseded by CapacityPool) | The conference-pass rule becomes data: "workshop ticket requires a conference pass in the same order/account." |
| **TicketPrice** [NEW] | ticket_type_id, label ("Early Bird"), amount_minor, currency, sale window, quantity_available/sold, hidden, position | Hi.Events tiered pricing. Introduced in P4/P7; until then TicketType.prices_minor suffices. |
| **CapacityPool** [NEW] | event_id, name, total_capacity (nullable=∞), used_capacity | pretix Quota: N ticket types draw one shared pool via `capacity_pool_memberships(pool_id, ticket_type_id)`. Row-locked in checkout alongside TicketType. |
| **Coupon** [SCOPE] | + event_id; code, percent XOR discount_minor, max_uses, uses_count, ticket_type scope → becomes `applies_to_ticket_type_ids` array, valid window, active, + `unlocks_hidden_tickets` bool, + `issued_to` (email/speaker/sponsor traceability), + single_use_per_email | Merges pretix Voucher + Alf.io SpecialPrice patterns. Bulk-generation + redemption audit in P7. |

### 3.4 Commerce

| Entity | Key fields | Notes |
|---|---|---|
| **Order** [SCOPE] | + event_id + organizer_id; code (unique **per event**), status, buyer fields, total_paise→total_minor, **gateway, currency, gateway_reference, country** (AD-2), coupon_id, expires_at, gstin, gst_legal_name, billing_state_code, metadata | `razorpay_order_id` backfilled into gateway_reference, then dropped. |
| **OrderItem** [NEW, P7] | order_id, ticket_type_id, ticket_price_id, quantity, unit_price_minor, discount_minor, tax_minor, total_minor, name_snapshot | Today line-item data is derivable from tickets; OrderItem lands with TicketPrice tiers so historical price/tier attribution survives renames. |
| **Ticket** (≈ Attendee/badge) [SCOPE] | + event_id; price_minor, secret, claim_token, attendee_name/email, checked_in_at (legacy json → superseded by CheckinRecord), tshirt/dietary/childcare (migrate to Question/Answer in P7, kept for DQOR continuity) | QR = opaque secret lookup, never PII in payload. |
| **Registration** [NEW] | event_id, user_id, ticket_id (nullable), attendance_state, payment_state (AD-5), source (self/host_added/import), unique (event_id, user_id) | The Luma RSVP layer. |
| **Payment** [NEW] | order_id, gateway, gateway_payment_id, status (created/authorized/captured/failed/refunded), amount_minor, currency, metadata jsonb | One row per payment attempt (pretix OrderPayment shape). PaymentEvent stays the immutable log; Payment is the queryable current-state row. |
| **PaymentEvent** [SCOPE] | + event_id (via order); + gateway, gateway_event_id, gateway_payment_id (unique (gateway, gateway_event_id)) | Immutable audit log, idempotency anchor. |
| **Refund** [SCOPE] | + event_id; + gateway, gateway_refund_id; amount_minor, status, credit_note_number, ticket_ids | Multiple partial refunds per order already supported — keep. |
| **Invoice** [SCOPE] | + event_id + organizer_id; kind gains `receipt_voucher`; number from InvoiceSequence; buyer_snapshot, line_items, immutable | Prefixes/series from TaxProfile, not `DQOR/` constants. |
| **InvoiceSequence** [NEW] | organizer_id, series (invoice/credit_note/receipt_voucher/commission), fiscal_year, last_number | FOR UPDATE increment. |
| **Payout** [NEW] | organizer_id, event_id (nullable), period, gross_minor, platform_fee_minor, fee_gst_minor, tcs_minor, tds_minor, net_minor, status, route_transfer_ids jsonb, provider_payout_ref | The settlement-waterfall ledger (AD-3). |
| **PayoutLine** [NEW] | payout_id, order_id, kind (sale/refund_clawback/fee/tcs/tds/adjustment), amount_minor | Per-order drill-down organizers reconcile against. |
| **WaitlistEntry** [NEW] | event_id, ticket_type_id (later ticket_price_id), email, name, user_id (nullable), status (waiting/offered/purchased/expired/cancelled), **offer_token**, **cancel_token**, offered_at, offer_expires_at, order_id, position | Hi.Events token-based offer/expiry/roll-forward flow, copied near-verbatim. |
| **CheckinRecord** [NEW] | event_id, ticket_id, direction (entry/exit), successful, failure_reason, scanned_at (client) vs recorded_at (server) — offline-sync friendly, device_id, operator_user_id, checkin_list_id (nullable; CheckinList itself deferred), program_session_id (nullable → session-level check-in) | Scan is a log, not a boolean. `Ticket#check_in!` writes here; `checked_in_at` becomes a denormalized convenience. |
| **GatewayCustomer / PaymentMethod** [NEW, deferred] | AD-2 token-only saved cards | Ships only if repeat-purchase is prioritized. |

### 3.5 Custom questions (EAV)

| Entity | Key fields | Notes |
|---|---|---|
| **Question** [NEW] | event_id, label, help_text, kind (short_text/long_text/boolean/single_choice/multi_choice/number/country/phone/date/file), required, options jsonb, belongs_to (order/attendee), ask_at (checkout/checkin/both), applies_to_ticket_type_ids array, dependency_question_id + dependency_values jsonb (branching), position, active | Superset of pretix/Hi.Events/Alf.io. Built-in templates: dietary, t-shirt, accessibility, emergency contact, pronouns, first-timer. |
| **Answer** [NEW] | question_id, order_id XOR ticket_id, value text / value_json | CSV export: one row per attendee, one dynamic column per active question. DQOR's tshirt/dietary/childcare columns migrate here. |

### 3.6 Conference module (optional per event; `events.settings["conference_module"]`)

| Entity | Key fields | Notes |
|---|---|---|
| **Track** [NEW] | event_id, name, color, text_color, position | Matches RubyEvents `schedule.yml` tracks — free export synergy. |
| **Room** [NEW] | event_id, name, floor, capacity, is_virtual, stream_url, accessibility_notes | Track (theme) and Room (place) are independent dimensions — never conflated. |
| **ProgramSession** [NEW] | event_id, track_id, room_id, title, abstract, description, kind (talk/keynote/workshop/panel/lightning/break/social), starts_at, ends_at, language, level, state (default `confirmed`; enum shaped for future CFP but no CFP UI — non-goal), slides_url, video_url, video_provider, max_attendees (workshop caps), position | AD-6 naming. |
| **Speaker** [NEW] | event_id, user_id (nullable), name, bio, photo, company, title, pronouns, github (bare username), twitter, mastodon (URL), bluesky, linkedin, speakerdeck, website | Field set matches RubyEvents `SpeakerSchema` 1:1 → export nearly free. Speaker = profile, not a user class. |
| **ProgramSessionSpeaker** [NEW] | program_session_id, speaker_id, role (speaker/co_speaker/moderator), position | |
| **PersonalScheduleEntry** [NEW] | registration_id, program_session_id, unique pair | "My agenda" + overlap-conflict warning + per-attendee .ics feed. None of the six OSS platforms model this — cheap differentiator. |
| **SponsorshipTier** [NEW] | event_id, name, description, level (int, lower=higher), price_minor, currency, max_slots, benefits jsonb (comp_tickets: 4, booth: true, …) | |
| **Sponsor** [NEW] | event_id, sponsorship_tier_id, name, slug, website, logo, description, badge ("WiFi Sponsor"), contact_name/email, entity_type (body_corporate/other → drives post-Jan-2025 sponsorship RCM logic) | Public fields map straight to RubyEvents `sponsors.yml`; commercial fields never exported. |
| **SponsorOrder** [NEW] | sponsor_id, tier_id, amount_minor, currency, status (pending/invoiced/paid/overdue/cancelled), signed_at, notes | Sponsor invoices ride the existing Invoice model (kind: sponsorship); payouts via RazorpayX. |
| **SponsorLeadScan** [NEW, deferred] | sponsor_id, ticket_id, scanned_by_user_id, scanned_at, notes, lead_status | Alf.io SponsorScan — distinctive paid-tier feature, post-P10. |

### 3.7 Networking & comms

| Entity | Key fields | Notes |
|---|---|---|
| **AttendeeProfile** [NEW] | user_id, event_id (nullable = platform-wide base + per-event overrides), visible_in_directory (default **false**), company, role_title, interest_tags array, looking_for text | Opt-in only; org-level kill switch. |
| **Connection** [NEW] | requester_id, recipient_id, event_id (nullable), status (pending/accepted/declined), unique pair | No raw-email reveal on accept; in-app contact or mutual opt-in reveal. Block/report from day one. |
| **EmailSequenceStep** [NEW] | event_id, trigger_type (on_registration/on_ticket_purchase/relative_to_event_start/relative_to_event_end/…), offset_seconds (for relative), subject, body (merge fields `{name} {event_title} {schedule_link} {ticket_link}`…), enabled, audience_filter jsonb (status/ticket-type) | OSEM `EmailSettings` pattern. Merge-field substitution only — **no template builder** (non-goal). Delivery via existing MailDeliveryJob; `EmailSequenceSend` log table guarantees at-most-once per (step, registration). |

---

## 4. DQOR migration strategy (production stays green throughout)

Principles: **additive expand/contract migrations only**, every step independently deployable and
reversible, DQOR's live sales/refunds/webhooks never interrupted, feature flags
(`Flipper` or a minimal `events.settings` flag — decide in P2, prefer the boring option:
env-var + settings jsonb, no new gem) around anything behavioral.

### 4.1 Backfill: DQOR becomes the first tenant

One reversible data migration (idempotent, runs after the tenancy tables exist):

1. Create `Account` ("Saeloun"/DQOR owner) → `Organizer` (slug `dqor`, payout_mode `direct`,
   PAN/entity from current records) → `TaxProfile` (copied from ENV `SELLER_NAME/ADDRESS/GSTIN`,
   sac `998596`, rate 1800bp, inclusive, invoice_prefix `DQOR/`, cn_prefix `DQOR-CN/`,
   registered_state_code `"27"`).
2. Create `Event` (slug `2026`, title "Deccan Queen on Rails 2026", starts/ends Oct 8–11 2026 —
   from the `CheckinsController::EVENT_DATES` constant being deleted — timezone Asia/Kolkata,
   venue_state_code `"27"`, currency INR, brand jsonb carrying current PDF/mailer copy).
3. Backfill `event_id` on all rows of ticket_types, coupons, orders, tickets, invoices, refunds,
   payment_events (batched `in_batches.update_all`, nullable column → backfill → `NOT NULL` +
   FK validation in a follow-up migration; standard 3-step for zero-lock).
4. `InvoiceSequence` seeded from `Invoice.maximum` per series/FY so numbering continues exactly.
5. Composite unique indexes added **concurrently** alongside old ones
   (`orders(event_id, code)`, `ticket_types(event_id, slug)`, `coupons(event_id, code)`), old
   global indexes dropped one deploy later.

### 4.2 De-hardcoding checklist (each its own small PR)

| Hardcoded today | Replacement |
|---|---|
| `TicketType#conference_pass?` = `slug.start_with?("conference-pass-")`; checkout's `validate_conference_pass!` + `LIKE 'conference-pass-%'` | `prerequisite_ticket_type_id` FK; `Orders::Checkout` validates "order contains/account owns the prerequisite type". DQOR backfill: point each workshop-type's FK at the conference-pass type. The slug method survives one release as a deprecated shim asserting parity in logs, then dies. |
| `CheckinsController::EVENT_DATES` (Oct 8–11 2026) | `Current.event.starts_at..ends_at` date enumeration; multi-day check-in json keyed by event dates. |
| `Gst.breakdown` state `"27"` + 18% | AD-4 signature; DQOR TaxProfile carries 27/1800bp → byte-identical output (assert in specs). |
| `DQOR/`, `DQOR-CN/` invoice prefixes; FY numbering in `Invoice` | TaxProfile prefixes + InvoiceSequence. |
| "Deccan Queen on Rails"/"Pune JN" in mailer subjects, PDF templates, ticket filenames | `event.brand` + organizer fields through locals; i18n for platform chrome. |
| ENV `SELLER_*` | TaxProfile (ENV read once by the backfill, then deleted from runtime). |
| Global Razorpay key pair | Per-organizer credentials (encrypted `organizers.gateway_credentials` via Rails encrypted attributes) with platform-level fallback; DQOR keeps using the same keys via fallback so nothing rotates during migration. |
| Routes: root→tickets#index single-event | Root becomes Discover (multi-event) **only in P10**; until then root 302s to `/dqor/2026`, preserving every deep link. Legacy URL paths (`/orders/:code`, `/tickets/find`) keep working permanently via non-tenanted lookups on globally-unique codes/secrets. |

### 4.3 Safety rails

- **Characterization spec pass before P2**: snapshot current invoice PDFs, mailer bodies, CSV
  exports for a seeded DQOR order; assert byte/semantic equality after tenancy lands.
- Webhook continuity: `/webhooks/razorpay` route kept as an alias to the new
  `/webhooks/gateways/razorpay` until Razorpay dashboard config is flipped and drained.
- Every backfill migration ships with a `down` that nulls the added columns; destructive drops
  (razorpay_* columns, old indexes) only after one full release cycle of dual-running.
- Deploy order within each phase: migrate (additive) → deploy code reading new+old → backfill →
  flip reads to new → deploy → drop old (next release).

---

## 5. Phased roadmap

Each phase = one independently shippable, fully tested PR-series with its own reversibility story.
Ordering rationale: tenancy first (everything depends on `event_id`), identity/RSVP second (every
later feature needs `User`), then commerce breadth, then conference depth, then polish/packaging.

**P1 is already done** (the current production app).

| Phase | Goal | Depends on |
|---|---|---|
| P2 | Tenancy foundation | — |
| P3 | User accounts, GitHub login, RSVP, Gravatar guest list | P2 |
| P4 | Multi-gateway + Stripe + geo routing | P2 |
| P5 | Sessions/speakers/agenda | P2 (P3 for personal agenda) |
| P6 | Sponsors + payouts (Route) | P2, P4 |
| P7 | Custom questions, codes, capacity pools, waitlist, exports | P2 (P3 for waitlist accounts) |
| P8 | Email sequences | P2, P3 |
| P9 | RubyEvents export | P5, P6 |
| P10 | Luma UI + OSS packaging | all |

### P2 — Tenancy foundation

- **Goal**: Account/Organizer/TaxProfile/Event exist; every commerce row is event-scoped; DQOR is
  tenant #1; zero user-visible change.
- **Models/migrations**: accounts, organizers, tax_profiles, memberships (table only — auth lands
  P3), events, invoice_sequences; `event_id` (+`organizer_id` on orders/invoices) across the seven
  commerce tables; composite unique indexes; backfill migration (§4.1); `prerequisite_ticket_type_id`;
  `venue_state_code`-driven `Gst`; TaxProfile-driven `Invoice`; Event-driven PDFs/mailers/check-in
  dates; `Current.organizer/event`.
- **Endpoints/UI**: `/:organizer_slug/:event_slug` public routes (old routes 302/alias); Avo
  resources for Account/Organizer/Event/TaxProfile; Avo Pundit scoping skeleton (superadmin-only
  for now).
- **Tests**: characterization pass (§4.3) green before/after; cross-tenant isolation request specs
  (seed 2 events, assert no leakage in every index/CSV/Avo resource); invoice-numbering continuity
  spec; checkout regression suite; conference-pass-gating parity specs (slug shim vs FK).
- **Risks**: silent scoping misses (mitigation: isolation specs + `strict_loading`-style review
  checklist); index swap on live orders table (mitigation: `algorithm: :concurrently`,
  `disable_ddl_transaction!`).
- **Reversibility**: nullable columns + kept old indexes for one release; backfill has full `down`.

### P3 — Accounts, GitHub login, RSVP, Gravatar guest list

- **Goal**: attendees have identities; free RSVP ("Register") works Luma-style; public guest-list
  avatar stack; "My events".
- **Models/migrations**: users, identities, sessions widened to users, registrations,
  memberships wired to auth; avatar fallback concern (`Avatarable`).
- **Endpoints/UI**: OmniAuth GitHub (`read:user user:email` only) + CSRF-safe callback; magic-link
  login; auth modal (Turbo Frame, post-auth resume); register card as `turbo_frame_tag
  "register_card"` swapping to confirmation in place; live guest count via Turbo Streams
  (`turbo_stream_from event`); `/me` (Going/Interested/Past + ICS feed); guest-list toggle on
  event settings; organizer staff login through the same User realm + Membership; Avo policies now
  enforce roles for real.
- **Tests**: OmniAuth request specs incl. email-linking and unverified-email non-linking; system
  specs (Cuprite) for browse→register→confirmation with and without prior session; registration
  state-machine unit specs; guest-list privacy specs (pending/waitlisted excluded from public
  stack; toggle off hides all).
- **Risks**: account-linking takeover via unverified emails (mitigation above); session fixation
  (rotate on login). GitHub OAuth outage → magic link is always present.
- **Reversibility**: registrations are additive; guest checkout path untouched, so disabling
  auth-gated features reverts to P2 behavior.

### P4 — Multi-gateway, Stripe, geo routing

- **Goal**: research doc 03 executed. Razorpay behind the port with zero behavior change; Stripe
  live for international buyers; router stamping gateway/currency/country on orders.
- **Models/migrations**: gateway/currency/gateway_reference/country on orders;
  gateway/gateway_event_id/gateway_payment_id on payment_events; gateway/gateway_refund_id on
  refunds; prices_minor on ticket_types; payments table; backfills; (defer gateway_customers /
  payment_methods).
- **Sub-PRs in strict order** (doc 03 §9): (1) additive schema+backfill dark; (2) extract
  `Payments::Gateway`+`RazorpayGateway` — pure refactor, review hardest; (3) unified
  `/webhooks/gateways/:gateway` + `WebhookProcessor` + generalized `PaymentEvent.record_webhook!`;
  (4) `Payments::Router` shipped dark (`DEFAULT_GATEWAY = :razorpay`); (5) `StripeGateway` +
  Payment Element checkout branch + `/payments/stripe/return`, env-gated; (6) flip default for
  non-IN to Stripe after the §6 compliance items clear.
- **Endpoints/UI**: checkout view branches on `order.gateway`; currency display + "Pay in USD
  instead" override link; Avo PaymentEvent gateway filter.
- **Tests**: existing Razorpay webhook/request/system suite green untouched through sub-PR 2–3
  (the regression oracle); Stripe adapter specs with stubbed API + signed-webhook fixtures; router
  unit specs (CF-IPCountry, XX sentinel, Accept-Language fallback, override cookie); idempotency
  specs (duplicate webhook, retried intent creation, double refund).
- **Risks**: behavior drift in the extraction (mitigation: no-diff test discipline);
  **Stripe-for-India export compliance is a launch blocker owned by §6, not engineering** —
  sub-PR 6 does not ship until signed off. Multi-currency invoices default to "flagged, GST
  treatment pending CA" state.
- **Reversibility**: each sub-PR independently revertable; router flip is a config change.

### P5 — Sessions, speakers, agenda (conference module v1)

- **Goal**: organizers publish a multi-track schedule; attendees build a personal agenda.
- **Models/migrations**: tracks, rooms, program_sessions, speakers, program_session_speakers,
  personal_schedule_entries; `events.settings["conference_module"]` toggle.
- **Endpoints/UI**: organizer schedule builder (custom Hotwire, not Avo: track/room/time grid,
  drag not required v1 — form-based slotting is fine); public `?tab=schedule` on the event page
  (tabs render only when module enabled); "My Schedule" (going-attendees only) with overlap
  warnings; per-attendee and full-event `.ics`; speaker profile pages with RubyEvents-compatible
  social fields.
- **Tests**: schedule rendering across timezones/multi-day; conflict-detection unit specs; ICS
  golden files; authorization (only going attendees save agendas; editors manage schedule).
- **Risks**: low — additive module, flag-gated per event. Naming collision handled by AD-6.
- **Reversibility**: toggle off hides everything; tables are leaf tables.

### P6 — Sponsors + payouts

- **Goal**: sponsor CRM with tiers and invoicing; Route-based marketplace settlement with the full
  TDS/TCS waterfall; sponsor logo wall on event pages.
- **Models/migrations**: sponsorship_tiers, sponsors, sponsor_orders, payouts, payout_lines;
  `organizers.payout_mode`, Route linked-account fields, encrypted gateway_credentials.
- **Endpoints/UI**: organizer sponsor pipeline (tier setup, sponsor records, generate B2B
  sponsorship invoice via existing Invoice engine, mark-paid/RazorpayX payout); comp-code issuance
  from tier benefits (uses P7 coupons if landed, else simple comp orders via existing
  `issue_comps!`); organizer payout dashboard (waterfall per §5.3 of doc 02); platform-side
  Route transfer creation on `mark_paid!` (payout_mode: route only); onboarding flow: PAN, entity
  type, GSTIN (strongly required before first payout), penny-drop validation, venue-state ≠
  GST-state CTP warning.
- **Tests**: waterfall math unit specs (the ₹1,000 worked example from doc 02 §5.3 as a golden
  spec); Route transfer stubbing via WebMock; TDS edge cases (no PAN → 5%, individual ≤₹5L
  exemption); sponsorship RCM branching on sponsor entity_type; payout ledger reconciliation specs.
- **Risks**: **highest-compliance phase** — Route onboarding, 194-O/TCS filing operations, GSTR-8
  are §6 items; DQOR itself stays `payout_mode: direct` so this ships to production dark and is
  exercised by the first true third-party organizer. Rates/thresholds strictly config.
- **Reversibility**: payout_mode per organizer; direct mode is untouched P2 behavior.

### P7 — Custom questions, codes, capacity pools, waitlist, exports

- **Goal**: commerce breadth — the Townscript parity phase.
- **Models/migrations**: questions, answers, ticket_prices, order_items, capacity_pools (+
  memberships), waitlist_entries, checkin_records; coupon upgrades (bulk generation,
  unlocks_hidden_tickets, issued_to, redemption audit); migrate DQOR tshirt/dietary/childcare
  columns to seeded Questions (columns kept read-only one release, then dropped).
- **Endpoints/UI**: question builder with built-in templates + branching; checkout renders
  order-level and per-attendee questions (ask_at checkout) and check-in surfaces ask_at-checkin
  ones; tier-aware ticket selector (Early Bird/Regular with windows + per-tier inventory);
  waitlist join on sold-out + offer emails with `offer_token` links + auto-roll on expiry
  (recurring job); check-in scanner writes CheckinRecord (entry/exit, offline batch-sync
  endpoint); dynamic-column CSV exports (attendees × active questions, filterable), coupon and
  redemption CSVs.
- **Tests**: EAV round-trip + branching-visibility specs; capacity-pool concurrency spec (the
  row-lock checkout test extended to shared pools); waitlist state machine incl. expiry
  roll-forward job; CSV golden files incl. DQOR legacy-column parity; check-in re-entry and
  offline-sync ordering.
- **Risks**: checkout hot path touched (pools + tiers) — mitigation: keep single-type fallback
  path, load-test the lock ordering (always lock pools after ticket_types, by id, to avoid
  deadlocks).
- **Reversibility**: tiers/pools optional per ticket type; waitlist per event flag.

### P8 — Email sequences

- **Goal**: predefined trigger emails with merge fields; Luma cadence out of the box
  (T-1day, T-1hour reminders, post-event thanks) as seeded default steps per event.
- **Models/migrations**: email_sequence_steps, email_sequence_sends (dedupe log).
- **Endpoints/UI**: per-event list of steps (enable/disable, edit subject/body, audience filter);
  send-history view. **No template builder** — plain merge-field text (non-goal).
- **Jobs**: immediate triggers off state transitions (registration created, order paid); relative
  triggers via a scheduler job scanning enabled steps hourly (`perform_at` windows), with
  at-most-once guaranteed by the sends log, not by scheduling accuracy.
- **Tests**: merge-field rendering; dedupe (job retries, event rescheduling moves send times);
  audience filtering; timezone correctness (offsets computed against event tz).
- **Risks**: duplicate sends on event-date edits (the sends log is the invariant); deliverability
  volume (existing MailDeliveryJob throttling reused).
- **Reversibility**: steps disabled by default for existing events; DQOR's current hardcoded
  mailer flows (confirmation, weekly assignment reminders) migrate into seeded steps only after
  parity specs pass.

### P9 — RubyEvents.org export

- **Goal**: one-click generation of the full RubyEvents YAML tree for a conference, validated
  against their schemas, delivered as a downloadable zip **and** an optional bot PR to a fork of
  `rubyevents/rubyevents` (it is a file+PR pipeline, not an API — research doc 05 §1.1).
- **Implementation**: `RubyEvents::Exporter` service producing `series.yml`, `event.yml`,
  `cfp.yml` (links only — we have no CFP), `involvements.yml`, `venue.yml`, `sponsors.yml`
  (public fields only — **pricing/invoice data never crosses this boundary**), `schedule.yml`
  (grid from ProgramSessions; empty-`items` slots auto-filled convention respected → videos.yml
  must be chronologically ordered), `videos.yml` (talks; `video_provider: "not_recorded"`
  pre-publication), speakers as an **append-only patch to global `speakers.yml` deduped by GitHub
  handle** with byte-identical name matching between videos/involvements and speaker entries —
  the identity rule their linter enforces. Client-side validation mirroring their Yerba schema
  rules (required fields, enums, IANA tz, date/ID regexes) before any PR.
- **Tests**: golden-tree spec against a seeded conference; schema-rule validator specs; dedupe
  specs (existing upstream speaker → alias, not duplicate).
- **Risks**: upstream schema drift — pin the vendored schema rules with a version note; export
  is lossy by design (no registration/payment data, ever).
- **Reversibility**: pure read-side feature.

### P10 — Luma-grade UI + OSS packaging

- **Goal**: the design-language pass and the "anyone can deploy this" release.
- **UI**: Luma-inspired CSS token system (§7) applied across event page (content-and-rail layout,
  sticky register card, icon-tile date rows via `DateIconComponent`, avatar stack, status pills),
  Discover homepage (popular events, categories, city filter) replacing the root redirect,
  organizer/"Calendar" pages with Follow + digest (Follow model + CalendarDigestMailer), curated
  per-event `theme` enum (no arbitrary CSS injection), dark-mode-correct.
- **Packaging**: `.env.example` complete; one-command deploy docs (Render blueprint + generic
  Docker/Kamal); seeds for a demo organizer/event; MIT/AGPL license decision (product-owner call —
  note pretix/Hi.Events chose AGPL to protect against closed SaaS forks; current repo carries an
  MIT-style LICENSE); rename/branding of the OSS project distinct from DQOR; public README,
  CONTRIBUTING, upgrade notes; CI matrix; remove any remaining Saeloun/DQOR assumptions
  (verified by booting a fresh instance with a non-DQOR seed and running the full system suite).
- **Tests**: full system-spec sweep on the new UI; accessibility pass (keyboard, contrast on
  tokens); fresh-install smoke script in CI.
- **Risks**: design drift — lock tokens from a live-Luma verification session first (doc 04 flags
  its hex values as directional); scope creep — Discover ships minimal (list + city filter),
  map view deferred.

---

## 6. Risks & human/CA sign-off items (NOT engineering calls)

These are legal/compliance decisions. Engineering builds the switches; a human — with a CA and,
where flagged, a fintech lawyer — throws them. Each blocks the phase listed.

| # | Item | Question for the professional | Blocks |
|---|---|---|---|
| S1 | **GST on USD/export ticket sales & LUT** | Is a Stripe/USD sale to a non-resident attending an India-venue event a zero-rated export under LUT, or does s.13(5) (POS = venue) make it a domestic supply requiring IGST? What documentation (LUT filing, FIRC/BRC per transaction) is required? | P4 sub-PR 6 (Stripe live) |
| S2 | **Stripe India posture — FIRA / PA-CB** | Stripe doesn't issue FIRA/FEMA export docs and isn't a licensed PA-CB for India-domiciled entities. Which entity holds the Stripe account (Indian entity? foreign subsidiary?), in which country, and is that compatible with FEMA + the org's audit needs? The answer changes the fee stack too. | P4 sub-PR 6 |
| S3 | **Casual Taxable Person registration** | For organizers running an event in a state where they hold no GST registration: confirm the CTP requirement (s.27), advance-deposit mechanics, and what the platform's onboarding guidance may/may not say (we warn; we must not give tax advice). | P6 onboarding copy |
| S4 | **PA licensing boundary / Route onboarding** | Confirm with counsel that the Route-linked-account architecture keeps the platform outside PA-authorisation scope for all planned flows (incl. sponsorship money and any refund top-ups), and complete Razorpay's marketplace/Route commercial onboarding. Any future fund-holding beyond the PA settlement cycle needs fresh review. | P6 (route mode) |
| S5 | **TDS/TCS operational filing** | Who files GSTR-8 monthly and deposits 194-O TDS / issues Form 16A? (RazorpayX automation vs. the CA's practice.) Confirm current rates (0.1% / 0.5% — both cut once already) and the individual/HUF ₹5L exemption handling at go-live. | P6 (first route payout) |
| S6 | **Receipt-voucher (Rule 50) practice** | Does the CA want advance sales documented as receipt vouchers with final invoice at event time, or is DQOR's invoice-on-payment practice acceptable? Sets each organizer's `invoice_timing`. | P2 config default (engine supports both) |
| S7 | **E-invoicing threshold & B2B IRN** | Confirm live threshold (₹5cr, possible ₹2cr change) and whether any pilot organizer needs IRP integration for corporate group registrations. | P6/P7 (B2B invoices) |
| S8 | **Sponsorship GST/RCM post-Jan-2025** | Confirm forward-charge (body-corporate sponsor) vs RCM (others) handling and what the platform's sponsorship invoice must show per entity type. | P6 sponsor invoicing |
| S9 | **OSS license choice** | MIT (max adoption) vs AGPL (protects against closed SaaS forks — pretix/Hi.Events precedent). Product-owner decision. | P10 |
| S10 | **NPCI UPI Collect phase-out** | Verify the actual NPCI circular before removing any Collect flow; checkout already defaults Intent-on-mobile / dynamic-QR-on-desktop via Razorpay Checkout, so exposure is low. | monitoring only |

Engineering-side top risks (owned by us): tenant-scoping leaks (isolation spec suite, P2);
payment-extraction behavior drift (no-diff discipline, P4); checkout-lock deadlocks with capacity
pools (lock-ordering rule + load test, P7); duplicate email sends (sends-log invariant, P8).

---

## 7. Tech choices

| Area | Choice | Notes |
|---|---|---|
| Framework | Rails 8.1, Ruby 4.0, Postgres, Solid Queue/Cache/Cable | Unchanged. No Redis, no Node build. |
| Frontend | **Hotwire (Turbo + Stimulus) + importmap + Propshaft** | Register card = Turbo Frame; live guest count = Turbo Streams; auth modal, avatar-fallback, map (later) = small Stimulus controllers. No SPA, no React. |
| CSS | **Luma-inspired token system** on vanilla CSS custom properties (current app has no Tailwind; introducing it is optional in P10 — tokens are framework-agnostic): warm off-white surface `#FAFAF9`, near-black text `#1C1917`, hairline borders `#E7E5E4`, near-black pill CTA, muted status pills (going=soft green, waitlist=soft amber, pending=soft indigo), 16px card radius, pill radius 999px. Typography per practicaltypography: Inter for UI, body 15–16px/1.6, title 28–36px semibold tight, uppercase 13px letter-spaced section labels. Verify exact values against a live Luma page before locking (doc 04 confidence note). | |
| Components | ViewComponent for the repeated primitives: `AvatarStackComponent`, `DateIconComponent`, `StatusBadgeComponent`, register card partials | One gem, high leverage; everything else stays partials. |
| Auth | **OmniAuth (`omniauth-github`, `omniauth-rails_csrf_protection`)** + hand-rolled magic link on existing MessageVerifier machinery. No Devise. | Scopes `read:user user:email` only. |
| Authorization | **Pundit** policies, shared between Avo (`authorization_client = :pundit`) and app controllers | Roles from Membership. |
| Admin | **Avo kept** for back-office (orders/refunds/invoices/payouts/platform ops), policy-scoped per AD-7; product surfaces (event editor, schedule builder, guest list, sequences) are custom Hotwire UI | |
| Payments | razorpay gem (existing), **stripe gem** (P4); adapters own all SDK contact | PayU/Cashfree deferred; port-shaped for ~150-line adapters. |
| Money | Integer minor units end-to-end; no money gem — a small `Money` helper module for formatting (`money(amount_minor, currency)` replacing `inr()`) | Alf.io lesson; renames in dedicated PRs. |
| PDFs/QR | Ferrum+Chromium and RQRCode unchanged; templates data-driven | |
| Geo | `CF-IPCountry` header (Cloudflare already in front); no MaxMind dependency | `XX` sentinel + Accept-Language fallback + `"IN"` default. |
| Email | Existing SMTP + MailDeliveryJob; sequences on top | No SendGrid/Postmark dependency for OSS default. |
| Testing | **RSpec throughout**: model/unit for state machines + tax math (golden waterfall spec), request specs for every endpoint + tenant isolation, WebMock-stubbed gateway specs with signed webhook fixtures, Cuprite system specs for the attendee journeys, characterization snapshots guarding DQOR outputs | Council-of-experts review + `bin/vite`-equivalent N/A (importmap) — JS changes verified in system specs per house rules. |
| Feature flags | Boring: ENV switches + `events.settings`/`organizers.settings` jsonb; no flag service | Route mode, Stripe default, conference module, waitlist, directory are all per-tenant settings anyway. |
| Maps (P10+) | Leaflet/MapLibre self-hosted tiles, progressive enhancement | No Google Maps key required for OSS deploys. |

---

## 8. Conference OS extension layer (P11–P14)

Added per product owner after the core roadmap: turn the platform into a full **conference OS** —
native mobile, on-site NFC, community/social, media, and post-production video. These **layer on**
the web platform (P2–P10) and reuse its models; none require abandoning Hotwire. External-account
gating (store review, Meta/Instagram app review, YouTube API verification) is owner-action, the same
class as the §6 sign-off items — engineering builds to ready-to-submit.

### P11 — Native mobile apps (iOS + Android) via Hotwire Native + NFC + push
- **Approach**: **Hotwire Native** — thin Swift (iOS) + Kotlin (Android) shells rendering the existing
  Hotwire web app, with native navigation/tab bar and **bridge components** for native capability.
  One product, native where it counts; avoids a second (React Native) codebase — budget + maintenance.
- **Native bridges**: (a) **NFC** — Core NFC (iOS) / `android.nfc` — badge-tap check-in and
  tap-to-connect networking (write attendee token to NTAG, read at booths/turnstiles);
  (b) camera/photo+video capture → direct upload (P13); (c) **push** (APNs/FCM) for schedule
  reminders, connection requests, organizer blasts; (d) offline check-in cache (Core Data / Room)
  syncing `CheckinRecord` on reconnect.
- **Backend**: JSON surface for the native-only bits (NFC token exchange, push registration, offline
  sync) alongside Turbo-rendered screens; `PushDevice(user_id, platform, token)` + an APNs/FCM job.
- **Release**: **Fastlane** lanes for build/sign/upload to TestFlight + Play Internal. Store
  publishing is account/signing/review-gated (owner's Apple Developer + Google Play accounts) —
  built to ready-to-submit; the submit step needs the owner's accounts.
- **Depends on**: P3 (identity), P10 (design tokens for in-app web screens).

### P12 — Social / community (Meetup + Eventbrite style)
- Per-event/organizer activity feed, event discussions/comments, attendee directory + connections
  (P3 networking extended; tap-to-connect via P11 NFC), **follow** organizers/"Calendars" with digest
  emails, lightweight DMs, notifications, and **moderation** (report/block + organizer queue).
  New: `Post`, `Comment`, `Reaction`, `Follow`, `Report`. Reuses `AttendeeProfile`/`Connection`.
- **Depends on**: P3.

### P13 — Media: upload + gallery + Instagram/social curation
- Attendee/organizer **photo & video upload** (Active Storage → R2, background transcode +
  thumbnails), per-event **gallery** with moderation and consent/rights flags. **Social curation**:
  ingest tagged posts from **Instagram** (Graph API hashtag/mention) and other networks into a curated
  event gallery, with display-rights handling (opt-in, attribution, takedown). New: `MediaItem`,
  `GallerySource`, moderation states. Instagram Graph API needs a Meta app + review (owner action).
- **Depends on**: P3, P10.

### P14 — YouTube post-production pipeline
- Post-event talk-video pipeline: OAuth to the organizer's YouTube channel, **upload recordings via
  the YouTube Data API** with per-talk metadata (title/description/tags/playlist from
  `ProgramSession`+`Speaker`+`Track`), unlisted→public publish scheduling, and **feed the resulting
  video IDs back into the P9 RubyEvents `videos.yml` export** — closing the loop recording → YouTube →
  RubyEvents. New: `VideoAsset(program_session_id, youtube_id, status)` + upload/publish jobs.
- **Depends on**: P5 (sessions/speakers), P9 (RubyEvents export). YouTube API OAuth verification +
  quota is owner action.

---

*Companion research (in the planning scratchpad, not committed): 00-codebase-map, 01-oss-platforms,
02-india-payments-compliance, 03-multi-gateway, 04-competitor-ux, 05-integrations-networking.
Doc 03 is effectively the P4 implementation spec; doc 02 §5.3 is the P6 golden test case;
doc 05 §1 is the P9 format contract.*
