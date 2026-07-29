# Open-Source Event/Ticketing Platforms: Data Model & Feature Research

Research date: 2026-07-29. Sources are primary (docs, GitHub source, live schema files) unless noted. Goal: inform the data model and feature set of a new open-source, India-first Rails-based event platform (Luma / Townscript / Eventbrite alternative).

---

## 1. Platform-by-platform notes

### 1.1 Pretix (Python/Django)

- **License**: AGPLv3, with additional terms ("pretix" name/branding restrictions, must keep "powered by pretix" notice on the free/Community tier). Business model is open-core: self-host free, or pay for SaaS/support/paid plugins. Source: [pretix/pretix](https://github.com/pretix/pretix), [pretix license blog post](https://pretix.eu/about/en/blog/20210412-license/).
- **Stack**: Django + PostgreSQL (required since 2023.6) + Redis for background tasks/Celery. Server-rendered admin ("control") plus a JS presale widget.
- **Maturity**: The most enterprise-grade / feature-complete of the group — used heavily by European conferences (DjangoCon, EuroPython, FOSDEM-adjacent events, Chaos Computer Club congresses). Excellent public docs including a documented [data model page](https://docs.pretix.eu/dev/development/implementation/models.html) and full [REST API resource reference](https://docs.pretix.eu/dev/api/index.html).
- **Key entities** (from docs + API resource list):
  - `User` — email-based login, permission checks scoped per Organizer/Team.
  - `Organizer` — top-level tenant; globally unique short "slug" used in URLs. Has plugins, isolated cache, own email backend config.
  - `Team` — collection of Users with access rights; scoped to "all events" or a specific subset of events under one Organizer. **This is pretix's answer to org-level RBAC.**
  - `Event` — belongs to one Organizer; has currency, presale from/to window, test-mode flag, sales-channel restrictions, plugin list.
  - `SubEvent` — a single date within an event **series** (e.g. a recurring workshop or a multi-city tour under one Event shell). Has its own date/presale/location, and can override item prices via `SubEventItem`/`SubEventItemVariation`. This is pretix's mechanism for "one Event with many occurrences."
  - `Item` (=Product/TicketType) — event-scoped, optional `ItemCategory`, default price + tax rate, admission flag ("is this an admission ticket vs. merch"), per-order min/max, sales-channel restriction, approval-required flag, validity mode (fixed dates vs. dynamic duration after purchase — useful for multi-day passes).
  - `ItemVariation` — variant of an Item (e.g. T-Shirt S/M/L), own price/approval/sales-channel overrides.
  - `ItemAddOn` — lets an Item offer optional add-ons from another ItemCategory, with a max count (e.g. "add up to 2 workshop seats to your conference ticket").
  - `Quota` — a shared inventory pool referencing one or more Items/Variations; this is how pretix does **shared capacity** ("500 total tickets across Early Bird + Regular + Student prices"). States: OK / RESERVED / ORDERED / GONE, cached ~120s for performance.
  - `Question` (+ `QuestionOption`) — attendee custom fields. Types: number, single-line string, multi-line text, boolean, single choice, multiple choice, file upload, date, time, datetime, **country (ISO 3166)**, **telephone**. Supports `dependency_question`/`dependency_values` (conditional/branching questions), `ask_during_checkin` + `show_during_checkin` (ask or reveal at the door, not just at purchase), `identifier` for stable external matching, `print_on_invoice`, validation constraints (min/max, file type "portrait" check for badge photos).
  - `Order` — code-based per-event ID, statuses PENDING/PAID/EXPIRED/CANCELED, "valid if pending" flag (treat unpaid-but-not-expired as valid, e.g. for invoice/bank-transfer orgs), buyer email/phone, secret token for self-service order modification links, expiration date for cart holds.
  - `OrderPosition` — one line item = one ticket; has its own `secret` used to generate the **QR code**, attendee name/email, tax detail, "blocked" status + reason, `valid_from`/`valid_until` (own validity window, independent of order).
  - `OrderFee` — fee lines added independently of items: payment fee, shipping, service fee, gift-card, other. Individually taxed and cancelable.
  - `OrderPayment` — one row per payment attempt; states created/pending/confirmed/failed/canceled/refunded; provider-specific JSON metadata (Stripe, PayPal, Razorpay-style gateway plug-ins are all separate provider backends).
  - `Voucher` — full discount-code entity, not just a percent-off string. Fields: `code`, `max_usages`, `redeemed`, `min_usages` (must-combine-N-uses), `valid_until`, `price_mode` (none/set/subtract/percent), `value`, `budget`/`budget_used` (spend cap across all redemptions), scoping to `item`/`variation`/`quota`/`subevent`/`seat`, `block_quota` (reserve inventory even before redeemed), `allow_ignore_quota` (bypass sold-out), `show_hidden_items` (unlocks items not publicly listed — the "secret sale" pattern), `tag` for grouping/reporting.
  - `Discount` — separate from Voucher: automatic, rule-based discounts (e.g. "buy 3+ get 10% off") not tied to a code.
  - `CheckinList` — named list scoped to an Event or SubEvent, `include_pending` flag (allow checking in unpaid-but-reserved orders, e.g. door payment).
  - `Checkin` — individual scan record: `successful`, `error_reason` (canceled/invalid/unpaid/rules/revoked), `datetime` vs `created` (logical vs. server time — supports offline scanning apps syncing later), `position` FK to OrderPosition, `auto_checked_in`, `gate`/`device` identifiers, `type` entry/exit (**supports re-entry / exit scanning**, not just one-way). Multiple check-in lists can be scanned together in one request as long as they're on different events (multi-event badge use case).
  - `TaxRule` — jurisdiction-based VAT/GST rule configuration, reusable across items.
  - `Invoice`, `Cart`/`CartPosition` (server-side reserved-cart-with-timeout during checkout).
- **Standout ideas for us**: SubEvent (event series/dates) is the cleanest OSS pattern for recurring/multi-date events. Quota as a decoupled inventory pool (rather than "quantity" living directly on the ticket type) is the cleanest shared-capacity model. Voucher separated from Discount (manual code vs. automatic rule) is a good split. Checkin as its own audit-log entity (not a boolean on Attendee) with entry/exit type is important for re-entry and analytics.

### 1.2 Alf.io (Java)

- **License**: GPLv3. Source: [alfio-event/alf.io](https://github.com/alfio-event/alf.io).
- **Stack**: Java 17, Spring, PostgreSQL 10+. Ships its own Gradle wrapper. Self-hosted only (no official SaaS), positions itself explicitly as the "privacy and fair pricing" option for conferences/meetups.
- **Key entities** (from `src/main/java/alfio/model/*` source, field-level):
  - `Organization` (`model/user/Organization.java`) — `id, name, description, email, externalId, slug`. Users linked via `UserOrganization` join table — i.e., **multi-tenancy is a flat Organization → Users join**, simpler than pretix's Team model (no per-event scoping baked into the core entity, though role-based access exists at the `Authority`/`Role` layer).
  - `Event` — `format` (enum: **IN_PERSON / ONLINE / HYBRID** — first-class hybrid-event support), `shortName` (slug), `displayName`, `websiteUrl`, `externalUrl`, `location`, `latitude/longitude`, `begin/end` (ZonedDateTime), `currency`, `vatIncluded`, `vat`, `allowedPaymentProxies` (list of enabled gateways per event), `privateKey` (used for signed QR payloads), `timeZone`, `locales` (bitmask of enabled languages), `status`.
  - `TicketCategory` (=TicketType) — `maxTickets`, `accessRestricted` (hidden/code-only category), `status`, `bounded` (finite vs. unbounded inventory), `code` (category-level access code), `validCheckInFrom/To` (**category can have its own check-in window**, e.g. VIP early access), `ticketValidityStart/End` (own usage validity), `ticketCheckInStrategy` and `ticketAccessType` enums (multi-strategy check-in: e.g. once-only vs. multiple-entry).
  - `Ticket` — `uuid` + `publicUuid` (two identifiers — one internal, one for QR/public sharing), `status` enum (FREE/PENDING/TO_BE_PAID/ACQUIRED/CHECKED_IN/CANCELLED/RELEASED/...), `ticketsReservationId` (FK to the cart/reservation, not directly to an Order — **Alf.io models the cart itself as a durable "TicketReservation" entity**), `lockedAssignment` (name can't be changed after issuance — for compliance), `srcPriceCts/finalPriceCts/vatCts/discountCts` (**prices stored in integer cents at every stage of the pricing pipeline** — avoids float rounding bugs), `extReference` (external system ID), `subscriptionId` (tickets can be redeemed via a season-pass/subscription, a newer Alf.io 2.x feature).
  - `TicketReservation` — the cart/order entity: `validity` (hold expiry), `status` enum, buyer name/email/billingAddress, `confirmationTimestamp`, `paymentMethod`, `promoCodeDiscountId`, `invoiceRequested`+`invoiceNumber`+VAT fields (**full VAT-invoice generation built in**, relevant for GST invoicing in India), `directAssignmentRequested` (buyer wants to assign all ticket names immediately vs. later via email links).
  - `SpecialPrice` — pre-generated per-category access/discount codes: `code`, `priceInCents`, `ticketCategoryId`, `status`, `recipientName/Email`, `sentTimestamp`. This is Alf.io's mechanism for "send 50 individual codes to reviewers/speakers, one-time-use, tied to a specific hidden category" — distinct from a general voucher pool.
  - `PromoCodeDiscount` — the general voucher/coupon entity: `promoCode`, `discountAmount`, `discountType` (%, fixed), `categories` (Set<Integer> — can restrict to specific ticket categories), `maxUsage`, `codeType` (DISCOUNT vs. ACCESS — same entity doubles as a hidden-category unlock code), `hiddenCategoryId`.
  - `AdditionalService` (+ `AdditionalServiceItem`, `BookedAdditionalService`) — **add-on products decoupled from tickets**: workshops, merch, donations, supplements. `AdditionalServiceType`, `SupplementPolicy` (mandatory/optional/one-per-ticket), `VatType`. This is Alf.io's version of pretix's ItemAddOn but implemented as its own purchasable line rather than a variation of Item.
  - `PurchaseContextFieldConfiguration` / `PurchaseContextFieldValue` — the modern (2.x) generic custom-field system, unifying "Question" across Events **and Subscriptions**: `context` enum (ATTENDEE/ADDITIONAL_SERVICE/...), `type`, `minLength/maxLength`, `restrictedValues` (choice options), `categoryIds` (scope a question to specific ticket categories only), `disabledValues`, `displayAtCheckIn` — direct equivalent of pretix's dietary/t-shirt/requirement questions.
  - `SponsorScan` — **dedicated lead-retrieval entity**: `userId` (the sponsor-booth operator), `eventId`, `ticketId` (attendee scanned), `notes`, `leadStatus` enum, `operator`. This is a first-class "sponsor badge-scanning app" data model — notable since most of the other OSS platforms have no sponsor lead-retrieval concept at all.
  - `Audit` — full changelog entity: `reservationId`, `eventType`, `entityType`, `entityId`, `modifications` (list of field-level diffs), actor identity. Useful reference for building an audit trail on Orders/Attendees.
- **Standout ideas for us**: SponsorScan (lead retrieval) is a distinctive, conference-specific feature worth stealing directly. SpecialPrice vs. PromoCodeDiscount (pre-generated single-recipient codes vs. general reusable coupon) is a useful split for speaker/press/reviewer comps. Storing all money as integer cents through the whole pricing pipeline is a good practice to copy. `TicketCategory.ticketAccessType`/hybrid event `format` are good primitives for hybrid/online events.

### 1.3 Hi.Events (PHP/Laravel + React)

- **License**: AGPL-3.0. Source: [HiEventsDev/Hi.Events](https://github.com/HiEventsDev/Hi.Events) (default branch `develop`).
- **Stack**: Laravel 12 (PHP 8.2+) backend with a repository/handler/domain-service layered architecture (DDD-flavored, not fat ActiveRecord), PostgreSQL via Eloquent, Redis for queues/cache; React + Mantine UI + LinguiJS (12+ languages) frontend. Newest and most actively developed of the group — the migration history runs into 2026 and shows very recent feature work (waitlists shipped 2026-02, occurrence-based recurring events 2026-02/03, Stripe Connect payouts + platform-fee/VAT handling through 2026-05/06). Good modern reference architecture for a Laravel-adjacent Rails app.
- **Key entities** (from live `backend/database/migrations/schema.sql` + later incremental migrations, field-level, verified directly against source):
  - `accounts` — top platform-level tenant (an "account" can own multiple `organizers`; this is Hi.Events' outermost multi-tenancy boundary, e.g. one signup = one Account, which can then create many Organizers/brands).
  - `organizers` — `account_id, name, email, phone, website, description, currency, timezone`. Has its own `organizer_settings`, `organizer_configuration`, `organizer_stripe_platforms`, `organizer_vat_settings` (VAT/GST config **per organizer**, not just per event — important for an India-first platform with GST registration per legal entity).
  - `events` — `account_id, user_id (creator), organizer_id, title, start_date, end_date, status, location(+location_details jsonb), currency, timezone, attributes(jsonb), short_id, ticket_quantity_available`. Later migrations add `type` + `recurrence_rule` and split into `event_occurrences` (a dedicated recurring-event/multi-date model, similar in spirit to pretix's SubEvent) with per-occurrence capacity/visibility overrides (`product_occurrence_visibility`, `product_price_occurrence_overrides`) and per-occurrence statistics tables.
  - `tickets` (renamed internally to **"products"** in 2024 migrations — `rename_tickets_to_products` — to reflect that a "ticket" can be any sellable product, not just admission) — `event_id, title, type (PAID/FREE/DONATION/...), sale_start/end_date, min/max_per_order, hide_before/after_sale, hide_when_sold_out, show_quantity_remaining, is_hidden_without_promo_code, "order" (sort position)`. Later: `product_categories`, `product_type`.
  - `ticket_prices` (i.e. `ProductPrice`) — **tiered pricing as a first-class child of a ticket/product**, not a variation: `price, label, sale_start_date, sale_end_date, initial_quantity_available, quantity_sold, is_hidden, "order"`. This is how Hi.Events implements Early-Bird/Regular/Late tiers under one ticket type, each with its own inventory and sale window.
  - `capacity_assignments` (+ `ticket_capacity_assignments` join) — **shared capacity pools** (pretix-Quota equivalent): `event_id, name, capacity, used_capacity, applies_to (EVENT or specific tickets), status`. Lets N ticket types draw from one shared inventory limit.
  - `promo_codes` — `code, discount, discount_type, applicable_ticket_ids (jsonb), expiry_date, attendee_usage_count, order_usage_count, max_allowed_usages`. Later migration adds `discount_applies_to`.
  - `orders` — `short_id, event_id, total_before_additions, total_refunded, total_gross, currency, first/last_name, email, status, payment_status, refund_status, reserved_until (cart hold), is_manually_created (organizer-created offline order), session_id, public_id, payment_gateway, promo_code_id/promo_code, address(jsonb), taxes_and_fees_rollup(jsonb), total_tax, total_fee`. Full-text trigram indexes on name/email/public_id for fast admin search.
  - `order_items` — one row per line item within an order: `quantity, ticket_id, ticket_price_id (which tier), item_name (snapshot), price, price_before_discount, total_tax, total_gross, total_service_fee, taxes_and_fees_rollup`.
  - `attendees` — `short_id, first/last_name, email, order_id, ticket_id, event_id` — one row per issued ticket/badge (equivalent of pretix's OrderPosition). Later additions: `locale`, `notes`, `event_occurrence_id`.
  - `questions` — `event_id, title, required, type, options(jsonb), belongs_to (ORDER vs ATTENDEE — i.e. a question can be asked once per order or once per attendee), "order", is_hidden`. Later migration adds `description` field.
  - `check_in_lists` (+ `ticket_check_in_lists` join, `attendee_check_ins`) — `name, description, expires_at, activates_at, event_id`; many-to-many with ticket types (a check-in list can cover a subset of ticket types, e.g. "VIP entrance" vs. "General entrance"); `attendee_check_ins` records `check_in_list_id, ticket_id, attendee_id, ip_address` — a scan-log entity, later gains `event_occurrence_id`, `order_id`, `public_visibility` (self-serve public check-in) and `is_system_default`.
  - `waitlist_entries` (added 2026-02) — `event_id, product_id (later migrated to product_price_id — waitlist is per price-tier, not just per product), email, first_name, last_name, status, offer_token, cancel_token, offered_at, offer_expires_at, purchased_at, cancelled_at, order_id, position, locale`. **Token-based offer/cancel flow**: when inventory frees up, the entry gets a time-limited `offer_token` link; if unclaimed by `offer_expires_at` it can roll to the next person; `cancel_token` lets the person self-remove. This is a clean, modern waitlist pattern worth adopting directly.
  - `invoices` — `order_id, account_id, invoice_number, issue_date, due_date, total_amount, status, items(jsonb), taxes_and_fees(jsonb), uuid`. Auto-generated tax invoices per order.
  - `order_refunds` — `order_id, payment_provider, refund_id (from gateway), amount, currency, status, reason, metadata(jsonb)` — supports partial refunds (amount need not equal order total) and multiple refund attempts per order.
  - `stripe_payments`, `stripe_customers`, `stripe_payouts`, `order_application_fees`, `order_payment_platform_fees` — full Stripe Connect marketplace/payout modeling (platform takes an application fee, organizer gets a Connect payout) — directly relevant to a "we host many organizers and take a platform cut" business model.
  - `taxes_and_fees` (+ `ticket_taxes_and_fees` join) — reusable tax/fee definitions attachable to specific ticket types (VAT, service fee, booking fee as separate line items).
  - `affiliates` — `code, event_id, sales_volume, unique_visitors` — referral/affiliate tracking baked in.
  - `messages` — bulk-messaging entity: `event_id, subject, message, type, recipient_ids/attendee_ids/ticket_ids (jsonb filters), sent_by_user_id, status, send_data`.
  - `event_statistics` / `event_daily_statistics` / `event_occurrence_statistics` — pre-aggregated rollup tables (unique_views, total_views, sales totals, tickets_sold, orders_created, refunds) updated incrementally rather than computed live — a solid pattern for an analytics dashboard at scale.
  - No sessions/speakers/tracks/sponsors tables exist anywhere in the schema — **Hi.Events is purely a ticketing/commerce platform, with zero conference-agenda features.** That gap is exactly what Open Event Server and Alf.io (partially) cover instead.
- **Standout ideas for us**: the account → organizer → event hierarchy (platform tenant vs. brand vs. event) maps well onto a multi-org SaaS. The waitlist's token-based offer/cancel/expiry flow is the best-designed waitlist of all six platforms and should be copied close to verbatim. ticket_prices as tiered pricing children + capacity_assignments as a separate shared-pool concept together give the same power as pretix's Quota+ItemVariation with a slightly simpler two-table shape. Stripe Connect application-fee/payout modeling is a direct template for Razorpay Route/Route-equivalent payouts to Indian organizers.

### 1.4 Attendize (Laravel)

- **License**: Attribution Assurance License (OSI-approved, permissive-with-attribution) — notably *not* copyleft, unlike the other five. Source: [Attendize/Attendize](https://github.com/Attendize/Attendize).
- **Stack**: Laravel (PHP), MySQL. **Effectively unmaintained** — migration history stops in 2021, no Laravel-version-currency, most forks on GitHub are stale student/course forks. Treat as a historical reference for a *simple* schema shape, not a template for production architecture.
- **Key entities** (from `app/Models/*.php` — fillable arrays + relationships, since there's no single schema dump):
  - `Account` — the tenant root (an Account owns Organisers, similar to Hi.Events' Account tier but flatter — Attendize has no separate multi-organizer concept beyond this single level).
  - `Organiser` — `AuthenticatableContract` implementer (an Organiser is itself a login-capable actor, not a role on a User) — `account, events, attendees, orders`. **Simpler/older RBAC model**: no Team/role table, the Organiser record IS the identity.
  - `Event` — relations to `questions, images, messages, tickets, affiliates, orders, account, organiser, attendees, access_codes, currency, stats`. Has an "embed" URL/HTML generator, GTM support, ICS feed generation, `getEventUrlAttribute` (organizer's public event page URL).
  - `Ticket` — relations to `event, orders, questions, reserved` (reserved-but-unpaid tracking is a separate concern from Order status). No tiered pricing entity — price lives directly on Ticket, so "Early Bird" requires creating a wholly separate Ticket row.
  - `EventAccessCodes` (+ pivot `ticket_event_access_code`) — hidden-ticket access codes, Attendize's equivalent of pretix's "show_hidden_items" voucher flag, implemented as its own table.
  - `Order` — `fillable: first_name, last_name, email, order_status_id, amount, account_id, event_id, taxamt`. Relations: `orderItems, attendees, account, event, tickets, payment_gateway, orderStatus`. Refund logic lives on the model itself (`getMaxAmountRefundable`, partial-refund helpers) rather than a separate Refund entity.
  - `Attendee` — `fillable: first_name, last_name, email, event_id, order_id, ticket_id, account_id, reference, has_arrived, arrival_time`. **Check-in is just two columns on Attendee** (`has_arrived` boolean + `arrival_time` timestamp) — no separate Checkin/scan-log entity, no multiple check-in lists, no entry/exit distinction. This is the simplest (and least capable) check-in model of the six platforms.
  - `Question` (+ `QuestionAnswer`, `QuestionOption`, `QuestionType`) — polymorphic answers via `questionable_id`/`questionable_type` (answer can belong to an Attendee or presumably an Order), scoped to `events` and `tickets` (question can be restricted to specific ticket types via a pivot).
  - `DiscountCode` — plain Eloquent model, minimal (no custom fields captured beyond framework defaults visible from field list).
  - `Affiliate`, `Message`, `EventStats` — present but thin.
  - No Voucher/Quota/Waitlist/CheckinList/Session/Speaker/Sponsor entities exist at all.
- **Standout ideas for us**: mostly a cautionary example — its simplicity (checkin as two Attendee columns, price on Ticket directly, no shared-capacity concept) is what NOT to do if you want tiered pricing, waitlists, or multi-list check-in later. Worth noting only as the "minimum viable schema" floor.

### 1.5 Eventyay / Open Event Server (Python, FOSSASIA)

- **License**: GPLv3. Source: [fossasia/open-event-server](https://github.com/fossasia/open-event-server) (API/backend), companion repos `open-event-frontend` (Ember.js SPA) and `eventyay` (newer unified product). In active development since 2014; production instance at eventyay.com is used for real conferences (FOSDEM-adjacent, FOSSASIA Summit).
- **Stack**: Flask + SQLAlchemy + PostgreSQL backend exposing a JSON:API-flavored REST API; Ember.js SPA frontend (older) moving toward a Vue.js stack in the newer `eventyay` product line. Deployed historically on GKE/Kubernetes.
- **This is the strongest conference-agenda platform of the six** — it is the only one with a full first-class Session/Speaker/Track/Room data model alongside ticketing.
- **Key entities** (from `app/models/*.py`, field-level, verified against source):
  - `Group` — the organizer/community entity: `name, user_id (owner), social_links(json), logo_url, banner_url, about, followers count`; has `roles` (many-to-many Users↔Groups via `UsersGroupsRoles`). **This is Open Event Server's multi-organizer/tenancy unit** — an Event optionally belongs to a `group_id`. Unlike pretix's Organizer, a Group here is more "community" than "company" (reflecting FOSSASIA's community-conference origins) but serves the same structural role.
  - `Event` — `identifier(slug), name, external_event_url, logo_url, starts_at/ends_at, timezone, online (bool), latitude/longitude, location_name, is_featured/is_promoted/is_demoted, is_chat_enabled/is_videoroom_enabled/is_document_enabled (built-in virtual-event support), description, privacy (public/private), state (draft/published), event_type_id/event_topic_id/event_sub_topic_id (categorization taxonomy), group_id, is_sessions_speakers_enabled, is_cfs_enabled (Call for Speakers toggle)`. Relations fan out to `track, microlocation, session, speaker, sponsor, exhibitors, tickets, roles(UsersEventsRoles), custom_form, faqs, feedbacks, attendees`.
  - `UsersEventsRoles` (+ `Role`) — per-event RBAC: `event_id, user_id, role_id` where `Role` is a named, reusable role table (`name, title_name`) — the same shape as pretix's Team but flattened to one row per user/event/role rather than a Team-of-many-users.
  - `Ticket` — `name, description, type, quantity, position, price, min_price/max_price (donation/pay-what-you-want range), is_fee_absorbed, sales_starts_at/ends_at, is_hidden, min_order/max_order, is_checkin_restricted, auto_checkin_enabled`. Relations: `tags(TicketTag), order_ticket, access_codes, discount_codes`. `min_price/max_price` on a single ticket type is a nice minimal way to support "pay what you want" without a separate pricing-tier entity.
  - `TicketHolder` (= Attendee) — by far the richest attendee-field model of the six: `firstname, lastname, email, address/city/state/country, job_title, phone, company, billing/home/shipping/work_address, work_phone, website, blog` + **social profile fields** `twitter, facebook, instagram, linkedin, github` + `gender, accept_video_recording, accept_share_details, accept_receive_emails (consent flags), age_group, home_wiki/wiki_scholarship (Wikimedia-specific fields — this project's FOSSASIA/Wikimedia lineage shows), birth_date, is_checked_in/is_checked_out/is_registered, device_name_checkin, checkin_times/checkout_times/register_times (string logs, not a relational scan table), complex_field_values(json) (free-form custom answers), native_language/fluent_language(json), is_badge_printed + badge_printed_at`.
  - `Order` (+ `OrderTicket` join with `quantity, price`) — `identifier, amount, address/city/state/country/zipcode, company, tax_business_info, user_id, event_id, marketer_id (affiliate/referrer), transaction_id, paid_via, payment_mode, brand/exp_month/exp_year/last4 (card display), stripe_token/stripe_payment_intent_id/paypal_token, status, cancel_note, discount_code_id, access_code_id, tickets_pdf_url`.
  - `AccessCode` — hidden-ticket unlock codes (`code, access_url, tickets_number, min/max_quantity, valid_from/valid_till, ticket_id, event_id`) — same purpose as pretix's hidden-item voucher and Attendize's EventAccessCodes.
  - `DiscountCode` — separate from AccessCode: `code, discount_url, value, type, is_active, tickets_number, min/max_quantity, valid_from/valid_till, used_for` (percentage/flat, scoped to event, tracked by a marketer/affiliate).
  - `CustomForms` (+ `CustomFormOptions`) — the attendee-question system: `field_identifier, form (which form this belongs to), type, name, description, is_required, is_included, is_fixed (system field vs. custom), position, is_public, is_complex (structured/multi-part answer), min/max (for numeric/length constraints), is_allow_edit`.
  - `Session` — full conference-talk model: `title, subtitle, short_abstract/long_abstract, comments (reviewer notes), language, level, starts_at/ends_at, track_id, microlocation_id (room), session_type_id, speakers (M2M), slides_url/slides(json), video_url/audio_url, signup_url, state (pending/accepted/rejected/confirmed — full CFP review workflow), submitted_at, submission_modifier, is_locked, complex_field_values(json), feedbacks count/rating`. Full call-for-papers lifecycle is modeled, not just a static agenda.
  - `Speaker` — `name, photo_url, short/long_biography, speaking_experience, email, mobile, website` + social links (`twitter, facebook, github, mastodon, linkedin, instagram`), `organisation, is_featured, position (job title), country/city/address, heard_from, sponsorship_required, speaker_positions(json), event_id, user_id (linked platform account)`.
  - `Track` — `name, description, color, event_id, position` — the classic conference "which room/theme does this talk belong to" grouping, distinct from `Microlocation` (physical room).
  - `Microlocation` — physical room/venue: `name, latitude/longitude, floor, room, hidden_in_scheduler, position, is_chat_enabled, is_global_event_room, video_stream_id` — supports hybrid/virtual rooms directly.
  - `Sponsor` — `name, description, url, level (integer — sponsor **tier ranking**), logo_url, event_id, type (Gold/Silver/Platinum-style label)`. Simple but present — the only one of the six besides Alf.io's SponsorScan to model sponsors at all, and the only one to explicitly rank tiers.
  - `UserCheckIn` / `VirtualCheckIn` — session-level check-in (distinct from event/ticket check-in): `ticket_holder_id, session_id, station_id, check_in_out_at` — lets you track which **sessions** an attendee actually walked into, not just whether they entered the venue. `VirtualCheckIn` does the same for online/hybrid sessions with `check_in_type, check_in_at/check_out_at`.
  - `Exhibitor`, `Faq`, `Feedback` (session ratings), `Page` (custom CMS pages per event) round out the conference tooling.
- **Standout ideas for us**: this is the reference implementation for "conference mode" — Session/Speaker/Track/Microlocation/Sponsor/CFP-workflow should essentially be lifted wholesale (with Rails naming) if the platform wants to be conference-capable, not just ticketing-capable. TicketHolder's breadth of consent/demographic/social fields is a good superset to draw from for custom-question defaults. Track vs. Microlocation (theme vs. physical room) as two separate dimensions is worth keeping distinct rather than collapsing into one "room" field.

### 1.6 Mobilizon (Elixir)

- **License**: AGPLv3+. Governance moved from Framasoft to the non-profit **Kaihuri** in 2024 (NLnet-funded). Source: `framagit.org/framasoft/mobilizon` (GitLab, bot-walled — not fetchable directly; structure cross-checked via a GitHub mirror, `babarot/mobilizon`, and `docs.mobilizon.org`).
- **Stack**: Elixir/Phoenix backend with Ecto/PostgreSQL, Vue.js frontend. **Federated via ActivityPub** — the same protocol family as Mastodon/PeerTube, so Mobilizon instances and even individual Mastodon users can follow/interact with Mobilizon groups and events.
- **Not a ticketing platform.** No payment processing, no paid tickets, no Orders/Tickets/Invoices anywhere in the schema. It only supports free RSVP-style participation and can hold a link out to an external ticketing tool. Relevant here purely for its **identity and multi-tenancy architecture**, which is structurally distinctive among the six.
- **Key entities** (from `lib/mobilizon/{actors,events}` Ecto schemas):
  - `Actor` — a **unified polymorphic identity table** for both individual people and organizing groups, distinguished by a `type` enum (`ActorType`: Person / Group / ...). Fields: `preferred_username, domain (null for local, hostname for remote/federated actors), name, summary, url/inbox_url/outbox_url/followers_url/following_url/shared_inbox_url` (full ActivityPub actor endpoints), `keys` (its cryptographic keypair for signing federated activities), `manually_approves_followers`, `openness`/`visibility` enums, `suspended`, `avatar/banner`, `user_id` (nullable — null for remote actors or Groups, set for local Person actors owned by a User). Relations: `organized_events, comments, feed_tokens, memberships (self-referential — Actors can be members of other Actors, i.e. a Person is a Member of a Group)`.
  - `Member` — join entity for Actor-in-Group membership with a role (admin/moderator/member/invited — the group-permission ladder).
  - `Follower` — Actor-follows-Actor edge (distinct from Member — following ≠ joining), used both for the social-graph and for federation subscription.
  - `Event` — belongs to an organizing `Actor` (which can itself be a Person or a Group — **so "who owns this event" is answered by the same Actor table as everything else**, not a separate Organizer model). Has `event_options` (a JSON-ish settings blob) and `event_participation_condition` (free / needs-approval / external-URL — the closest thing to a "ticket type," but always free).
  - `Participant` — Actor-attends-Event edge with a `role` enum (`participant`, plus not_approved/rejected/moderator-style states referenced elsewhere in the codebase) — this is Mobilizon's "Attendee," and it's a pure join row (Actor × Event × role), not a separately-issued ticket/badge entity.
  - `Session`/`Track`/`Tag` also exist in the `events` context (a lightweight schedule/session model), plus `Comment`, `Report` (moderation), `FeedToken` (private iCal-style feed subscriptions).
- **Standout ideas for us**: the unified Actor table (Person and Group are the same underlying entity, distinguished by type, with a self-referential Membership graph) is an elegant identity model for federated/social software but is **probably more complexity than an India-first ticketing platform needs** — a conventional User/Organizer split (as pretix, Hi.Events, and Open Event Server all use) is simpler and better suited to a commerce-heavy product. The one idea worth borrowing regardless: `event_participation_condition` as an explicit enum (free / approval-required / external-registration) is a clean way to represent "this specific Event doesn't sell tickets through us at all," useful for a platform that might list free meetups alongside paid conferences.

---

## 2. Cross-platform comparison

| Platform | License | Stack | Multi-org unit | Recurring/series events | Tiered pricing | Shared capacity pool | Waitlist | Check-in model | Conference (sessions/speakers) | Sponsor tiers |
|---|---|---|---|---|---|---|---|---|---|---|
| **Pretix** | AGPLv3 | Django/Postgres/Redis | Organizer → Team (RBAC) | SubEvent | ItemVariation + SubEventItem price overrides | Quota (decoupled pool) | ❌ (core); via 3rd-party plugin only | CheckinList + Checkin (entry/exit, multi-list scan, offline-sync friendly) | ❌ | ❌ |
| **Alf.io** | GPLv3 | Java/Spring/Postgres | Organization → User join | ❌ (single Event only) | TicketCategory (separate rows) | TicketCategory.maxTickets (bounded) | ❌ | Category-level check-in window + strategy enum | ❌ | ❌ (but has SponsorScan lead-retrieval) |
| **Hi.Events** | AGPL-3.0 | Laravel/React/Postgres/Redis | Account → Organizer(s) | event_occurrences (2026) | ticket_prices (tiers per product) | capacity_assignments | ✅ token-based offer/cancel flow | check_in_lists (scoped to ticket subsets) + attendee_check_ins scan log | ❌ | ❌ |
| **Attendize** | Attribution Assurance (permissive) | Laravel/MySQL, unmaintained | Account → Organiser (flat) | ❌ | ❌ (price on Ticket row) | ❌ | ❌ | 2 columns on Attendee only | ❌ | ❌ |
| **Open Event Server / Eventyay** | GPLv3 | Flask/SQLAlchemy/Postgres, Ember/Vue | Group → User roles | ❌ (single Event) | min_price/max_price range only | ❌ | ❌ | UserCheckIn (session-level) + basic ticket check-in | ✅✅ Session/Speaker/Track/Microlocation + full CFP workflow | ✅ Sponsor.level + type |
| **Mobilizon** | AGPLv3+ | Elixir/Phoenix/Postgres, Vue | unified Actor (Person=Group) | ❌ | N/A (no ticketing) | N/A | N/A | N/A | lightweight Session/Track | ❌ |

**Takeaway**: no single OSS platform combines Hi.Events' modern commerce/payments architecture with Open Event Server's conference-agenda depth and pretix's Quota/SubEvent inventory sophistication. A new platform should synthesize: **pretix's Quota + SubEvent** (inventory/recurrence), **Hi.Events' waitlist + Stripe-Connect-style payout modeling** (adapted to Razorpay Route for India), **Open Event Server's Session/Speaker/Track/Sponsor** (conference mode), and **Alf.io's SponsorScan** (lead retrieval) and cents-integer money handling.

---

## 3. Canonical data model synthesis

Common entities that recur (in some form) across at least 4 of the 6 platforms, which is why they belong in a canonical schema:

- Organizer/Team, Event, TicketType/Product(+tiers), Order, Ticket/Attendee, Coupon/Voucher, Question/CustomField, Check-in(-list). Present in Pretix, Alf.io, Hi.Events, Attendize, Open Event Server in near-identical shape.
- Waitlist: only Hi.Events (recently). Worth including natively rather than bolting on later.
- Session/Speaker/Sponsor/Track: only Open Event Server (deep) + Alf.io (SponsorScan only). Should be modeled as an **optional conference module** on top of the ticketing core, not forced onto every event.
- Payout/Settlement: only Hi.Events models this in depth (Stripe Connect). Necessary for a hosted multi-organizer platform that takes a platform fee — directly maps to Razorpay Route for an India-first product.

### 3.1 Recommended entities, key fields, relationships

Below, `snake_case` fields, Rails-flavored (would map to ActiveRecord models + migrations). PK is always `id: bigint`. All money fields as `integer` (smallest currency unit / paise) per Alf.io's cents-pipeline lesson, never `float`.

```
Account                              # platform-level tenant / billing entity (Hi.Events-style)
  name, billing_email, country, gst_number (nullable), status
  has_many :organizers

Organizer                            # a "brand" — pretix Organizer / Alf.io Organization / Hi.Events Organizer
  account_id (fk)
  name, slug (unique, url-safe), logo_url, description, website
  support_email, support_phone
  default_currency (default "INR"), default_timezone (default "Asia/Kolkata")
  gst_number, pan_number, razorpay_account_id (for Route sub-merchant payouts)
  has_many :events
  has_many :teams / has_many :memberships, through: users  # RBAC

Team / Membership                    # pretix-style RBAC: users scoped to all-or-some events under an Organizer
  organizer_id, user_id, role (owner/admin/editor/checkin_operator/viewer)
  all_events (bool), has_many :team_event_scopes (if all_events = false)

Event
  organizer_id (fk)
  title, slug, description, status (draft/published/archived/cancelled)
  format (in_person/online/hybrid)                      # Alf.io idea
  starts_at, ends_at, timezone
  venue_name, address, latitude, longitude
  is_series (bool), recurrence_rule (nullable, iCal RRULE string)  # pretix SubEvent / Hi.Events occurrences
  currency, locale_default, supported_locales (array)
  visibility (public/unlisted/private), requires_approval (bool)
  cover_image_url
  has_many :event_occurrences (if is_series)
  has_many :ticket_types, :orders, :attendees, :questions, :checkin_lists,
           :coupons, :sessions, :sponsors, :speakers

EventOccurrence                      # pretix SubEvent / Hi.Events event_occurrences — one date within a series
  event_id, starts_at, ends_at, venue overrides (nullable), capacity_override (nullable)
  is_public, is_cancelled

TicketType (Product)
  event_id, category_id (nullable fk -> TicketCategory for grouping/sort)
  name, description, kind (paid/free/donation)
  min_per_order, max_per_order
  sale_starts_at, sale_ends_at
  is_hidden, is_hidden_without_code (voucher-gated), hide_when_sold_out
  requires_approval (bool)                               # pretix "approval-required"
  has_many :price_tiers (TicketPrice)
  has_many :capacity_memberships, through: CapacityPool  # shared-inventory support
  has_many :question_assignments

TicketPrice                          # Hi.Events ticket_prices — Early Bird / Regular / Late, etc.
  ticket_type_id, label, amount_cents, currency
  sale_starts_at, sale_ends_at
  quantity_available (nullable = unlimited), quantity_sold
  is_hidden, position

CapacityPool                         # pretix Quota / Hi.Events capacity_assignments
  event_id, name, total_capacity (nullable = unbounded), used_capacity
  has_many :ticket_types, through: capacity_pool_ticket_types  # which types draw from this pool

Coupon                               # merges pretix Voucher + Discount, Alf.io PromoCodeDiscount/SpecialPrice
  event_id, code (nullable — null means "automatic rule discount")
  kind (fixed_amount/percent/set_price)
  amount_cents_or_percent
  max_redemptions (nullable), redemptions_count
  valid_from, valid_until
  applies_to_ticket_type_ids (array/jsonb, empty = all)
  unlocks_hidden_tickets (bool)      # pretix show_hidden_items / Attendize EventAccessCodes
  is_single_use_recipient (bool), recipient_name, recipient_email  # Alf.io SpecialPrice pattern
  budget_cap_cents (nullable), budget_used_cents

Order
  event_id, buyer_name, buyer_email, buyer_phone
  status (pending/paid/partially_refunded/refunded/cancelled/expired)
  currency, subtotal_cents, discount_cents, tax_cents, fee_cents, total_cents
  coupon_id (nullable)
  reserved_until (cart hold expiry)
  is_manually_created (organizer/offline order)
  public_token (for buyer-facing "manage my order" links)
  invoice_number (nullable), gst_invoice_data (jsonb)
  has_many :order_items, :attendees, :payments, :refunds

OrderItem
  order_id, ticket_type_id, ticket_price_id
  quantity, unit_price_cents, discount_cents, tax_cents, total_cents
  item_name_snapshot                 # protects historical orders from later renames

Attendee (Ticket/Badge)              # pretix OrderPosition / Hi.Events attendees
  order_id, order_item_id, event_id, event_occurrence_id (nullable), ticket_type_id
  first_name, last_name, email
  qr_secret (unique, unguessable)    # pretix "secret" pattern
  status (valid/cancelled/transferred)
  checked_in_at (denormalized convenience; source of truth is CheckinRecord)
  valid_from, valid_until (nullable — supports multi-day pass windows independent of order)

Payment
  order_id, provider (razorpay/stripe/offline/bank_transfer), provider_ref
  status (created/pending/captured/failed/refunded), amount_cents, currency, metadata (jsonb)

Refund
  order_id, payment_id (nullable), amount_cents, currency, reason, status, provider_ref

Payout / Settlement                  # Hi.Events Stripe Connect analogue, for Razorpay Route
  organizer_id, period_start, period_end
  gross_cents, platform_fee_cents, tax_withheld_cents, net_cents
  status (pending/processing/paid/failed), provider_payout_ref

Question (CustomField)
  event_id, label, help_text, type (short_text/long_text/boolean/single_choice/multi_choice/
    file/date/time/datetime/country/phone/number)
  required, options (jsonb, for choice types)
  belongs_to (order/attendee)        # Hi.Events distinction: asked once per order vs. once per attendee
  ask_at (checkout/checkin/both)     # pretix ask_during_checkin
  dependency_question_id, dependency_values (jsonb)   # conditional/branching questions
  applies_to_ticket_type_ids (array, empty = all)
  position

QuestionAnswer
  question_id, order_id (nullable), attendee_id (nullable), value (text/jsonb)

Waitlist Entry                       # Hi.Events pattern — best-in-class of the six
  event_id, ticket_price_id, email, first_name, last_name
  status (waiting/offered/purchased/expired/cancelled)
  offer_token (unique), cancel_token (unique)
  offered_at, offer_expires_at, purchased_at, cancelled_at
  order_id (nullable, set once converted), position

CheckinList
  event_id, event_occurrence_id (nullable), name, description
  activates_at, expires_at
  public_self_checkin (bool)
  has_many :ticket_types, through: checkin_list_ticket_types  # scope to VIP/General/etc.

CheckinRecord                        # pretix Checkin — the scan log, not a boolean
  checkin_list_id, attendee_id
  direction (entry/exit)              # supports re-entry tracking
  successful (bool), failure_reason (already_checked_in/invalid/unpaid/revoked/wrong_list)
  scanned_at, recorded_at (logical vs. server time — offline-scanner sync support)
  device_id, gate_label, operator_user_id, ip_address

-- Conference module (optional per event) --

Track
  event_id, name, color, position

Room (Microlocation)
  event_id, name, floor, capacity, is_virtual, stream_url

Session
  event_id, track_id (nullable), room_id (nullable)
  title, subtitle, short_abstract, long_abstract
  starts_at, ends_at, level, language
  state (proposed/accepted/rejected/confirmed)   # CFP workflow, Open Event Server pattern
  slides_url, video_url
  has_many :speaker_sessions, through: speakers
  has_many :personal_schedule_entries        # "add to my schedule" for attendees

Speaker
  event_id, user_id (nullable, if speaker has a platform account)
  name, bio, photo_url, title, company
  twitter, linkedin, github, website

SpeakerSession (join)
  speaker_id, session_id, role (speaker/co-speaker/moderator)

PersonalScheduleEntry                 # attendee's "my agenda" — none of the 6 platforms model this
  attendee_id, session_id

Sponsor
  event_id, name, tier (platinum/gold/silver/bronze/custom), logo_url, url, description, position

SponsorLeadScan                       # Alf.io SponsorScan — distinctive, worth adopting
  sponsor_id, attendee_id, scanned_by_user_id (booth operator), scanned_at, notes, lead_status
```

### 3.2 How multi-event / multi-organizer (multi-tenancy) is modeled across platforms — synthesis

- **Pretix**: `Organizer` (tenant) → `Team` (named group of Users with all-events-or-scoped-events access) → `Event`. Cleanest RBAC of the six because Team is reusable across multiple people at once (invite a Team, not one user at a time).
- **Alf.io**: `Organization` → `UserOrganization` join (flat, no per-event scoping at the DB layer; scoping handled by a separate role/authority system).
- **Hi.Events**: `Account` (platform tenant, e.g. one signup) → `Organizer` (brand, an Account can run several) → `Event`. Adds a second tier above Organizer that the others lack — useful if one legal/billing entity runs multiple sub-brands.
- **Attendize**: `Account` → `Organiser` (the Organiser record doubles as the login identity — simplest but least flexible; can't have multiple people access one Organiser without sharing credentials... actually it does have a `users` table too but the model is thinner).
- **Open Event Server**: `Group` (community/org) ← `UsersGroupsRoles`, and separately `UsersEventsRoles` for direct per-event roles — i.e. **two independent RBAC layers**, one at the Group level and one at the Event level, which can be redundant/confusing.
- **Mobilizon**: unified `Actor` polymorphic table (Person and Group are the same table, `type` discriminates) with a self-referential `Member` (join-a-group) and `Follower` (subscribe-to) graph — powerful for federated social software, overkill for a commerce platform.

**Recommendation for the new platform**: adopt Hi.Events' two-tier `Account → Organizer` split (useful for agencies/venues running multiple event brands under one billing relationship — common in the India market with event-management companies running many client brands) combined with pretix's `Team`/role model for RBAC within an Organizer (owner/admin/editor/checkin-operator/finance-viewer), rather than Open Event Server's two-independent-RBAC-layers approach or Attendize's identity-is-the-tenant approach.

---

## 4. Check-in / QR, waitlist, refunds, custom questions — deep notes

### Check-in / QR
- **Universal pattern**: every ticketing-capable platform issues a unique per-ticket secret (`OrderPosition.secret` in pretix, `Ticket.uuid`/`publicUuid` in Alf.io, `Attendee.short_id` in Hi.Events) that's encoded into a QR code and looked up (not decrypted) at scan time — never encode PII or price into the QR payload itself, just an opaque token.
- **Multiple check-in lists per event** (pretix `CheckinList`, Hi.Events `check_in_lists`) is the standard way to support "VIP entrance," "workshop room," "general admission" as independently scannable gates, each scoped to a subset of ticket types.
- **Scan is a log entity, not a boolean.** Only Attendize collapses check-in to two columns on Attendee; every other platform (pretix `Checkin`, Hi.Events `attendee_check_ins`, Open Event Server `UserCheckIn`) keeps a append-only scan log, which is what enables entry/exit (re-entry) tracking, multiple-scanner-device conflict detection, and post-event analytics ("what time did the doors get busy").
- **Offline-first scanning**: pretix's `datetime` (logical, client-reported) vs `created` (server-received) split exists specifically so a scanning app can work offline and sync a batch of scans later without losing the true scan order — worth replicating.
- **Session-level check-in** (Open Event Server's `UserCheckIn`/`VirtualCheckIn` scoped to a `session_id`) is a conference-specific extension worth including in the conference module — lets organizers know real session attendance, not just venue entry.

### Waitlist
- Only Hi.Events has this natively; its design (2026) is the best reference: `status` state machine (waiting → offered → purchased/expired/cancelled), separate `offer_token`/`cancel_token` for self-service email links, `offer_expires_at` so an unclaimed offer can be reissued to the next person automatically, and — critically — the waitlist is scoped to a **price tier**, not just the ticket type, so "waitlist for Early Bird" and "Early Bird sold out, buy Regular now" can coexist correctly.

### Refunds
- **pretix**: `OrderPayment` state machine handles refund as a payment-state transition; supports partial refunds implicitly through fee/position-level cancellation.
- **Hi.Events**: dedicated `order_refunds` table, decoupled from `orders`/`payments` — supports **multiple partial refunds per order**, each tracking its own provider refund ID, amount, currency, and reason. This is the cleanest of the six and should be the template — model Refund as its own append-only entity referencing Order (and optionally a specific Payment), not a status flag on Order.
- **Attendize**: refund logic is computed on the Order model itself (`getMaxAmountRefundable`) with no persisted Refund row — acceptable for MVP but doesn't survive an audit or multiple partial refunds cleanly.

### Attendee custom questions (dietary, t-shirt size, requirements, etc.)
- Universal shape: a `Question` (event-scoped, typed, optionally required) plus an `Answer` join to either an Order or an Attendee. The **belongs_to (order vs. attendee)** distinction (Hi.Events, implicitly also pretix/Alf.io) matters: "dietary requirement" and "t-shirt size" are per-attendee, but "company GST number for invoice" or "how did you hear about us" are per-order.
- **Conditional/branching questions** (pretix's `dependency_question`/`dependency_values`) are worth including from day one — e.g. only show "please specify your dietary requirement" as a free-text field if the choice question "any dietary restrictions?" was answered "yes."
- **Scoping to specific ticket types** (Alf.io `PurchaseContextFieldConfiguration.categoryIds`, Attendize's ticket-question pivot, Open Event Server's per-form fields) — needed so a "which workshop track do you want?" question only appears for attendees who bought the workshop-add-on ticket.
- **Ask-at-checkin** (pretix `ask_during_checkin`/`show_during_checkin`) supports the common conference need of collecting or displaying a piece of info (e.g. allergy) at the door, not just at purchase.
- Recommended type enum, superset of all six: `short_text, long_text, boolean, single_choice, multi_choice, number, file_upload, date, time, datetime, country, phone`.

---

## 5. What's specifically good for conferences (sessions, personal schedule, speakers, sponsors)

Only **Open Event Server / Eventyay** takes this seriously; the other ticketing-focused platforms (Pretix, Alf.io, Hi.Events, Attendize) have none of it natively (pretix and Alf.io have marketplace plugins for some of this, but it's not core). Key patterns worth adopting:

1. **Track vs. Room (Microlocation) as two independent dimensions** — a session has a topical track ("Backend," "Design") and a physical location ("Room 302" or a livestream URL) that vary independently; don't conflate them into one field.
2. **Full CFP (Call for Papers/Speakers) lifecycle on Session**: `state` enum (proposed → accepted/rejected → confirmed), `is_cfs_enabled` toggle on Event, submission timestamps, reviewer comments — lets the same Session entity serve the submission/review workflow and the final published agenda without a separate "Talk Proposal" model.
3. **Speaker as (optionally) linked to a platform User account**, with rich bio/social fields — supports both "invited speaker with no login" and "speaker self-service portal" without two separate entities.
4. **Sponsor tiers as an explicit rank** (`level`/`type` on Sponsor) rather than free-text, so the presale page can auto-sort/group sponsor logos by tier.
5. **Personal schedule / "my agenda"**: none of the six platforms researched model this explicitly as a table (Open Event Server's frontend builds it client-side from favourited sessions via `user_favourite_session`), but it's straightforward to add as `PersonalScheduleEntry(attendee_id, session_id)` and is a high-value, low-effort addition for a modern conference product — genuinely worth doing better than any of the six here.
6. **Sponsor lead retrieval** (Alf.io's `SponsorScan`) is the one sponsor-specific commerce feature — sponsors want to badge-scan attendees at their booth and export leads; this is a frequently-requested paid add-on in commercial platforms (Cvent, Eventbrite Boost) that none of the free/OSS options except Alf.io implement, so it's a good differentiator to build.
7. **Session-level check-in** (`UserCheckIn`) — lets organizers report real per-session attendance/room utilization, distinct from overall event check-in.

---

## Sources

- Pretix: [Data model](https://docs.pretix.eu/dev/development/implementation/models.html), [REST API index](https://docs.pretix.eu/dev/api/index.html), [Questions](https://docs.pretix.eu/dev/api/resources/questions.html), [Check-in](https://docs.pretix.eu/dev/api/resources/checkin.html), [Vouchers](https://docs.pretix.eu/dev/api/resources/vouchers.html), [Concepts](https://docs.pretix.eu/dev/development/concepts.html), [License blog post](https://pretix.eu/about/en/blog/20210412-license/), [GitHub](https://github.com/pretix/pretix)
- Alf.io: [GitHub source](https://github.com/alfio-event/alf.io) (`src/main/java/alfio/model/*` read directly), [alf.io](https://alf.io/)
- Hi.Events: [GitHub source](https://github.com/HiEventsDev/Hi.Events) (`backend/database/migrations/schema.sql` and full migration history read directly), [README](https://github.com/HiEventsDev/Hi.Events/blob/develop/README.md)
- Attendize: [GitHub source](https://github.com/Attendize/Attendize) (`app/Models/*.php`, `database/migrations/*` read directly)
- Open Event Server / Eventyay: [GitHub source](https://github.com/fossasia/open-event-server) (`app/models/*.py` read directly), [FOSSASIA blog](https://blog.fossasia.org/tag/open-event-server/)
- Mobilizon: [docs.mobilizon.org — About](https://docs.mobilizon.org/about/), [Wikipedia](https://en.wikipedia.org/wiki/Mobilizon), GitHub mirror `babarot/mobilizon` (`lib/mobilizon/{actors,events}/*.ex` read directly, structure cross-checked, may lag current framagit.org source by a few versions)
