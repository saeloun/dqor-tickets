# Published owned events API v1

This default-off read contract is integrated with the iOS and Android owned-event consumers. Their production entry remains disabled; integrating the source does not activate production browsing or distribute either app. Existing DQOR programme, staff and attendee APIs stay separate. The canonical legacy event ID remains `dqor-2026`; this API neither aliases it nor changes staff authorization.

Enablement requires both `ORGANIZER_PLATFORM_ENABLED=true` and `PUBLIC_EVENTS_ENABLED=true`. Missing gates return the same non-cacheable 404 as a missing published event. This branch does not enable either flag, provision an organization, publish an event or change production configuration. No migration, import, scheduler, credential or native scope is added.

## Requests and public ownership

Anonymous HTTPS GET `/api/public/v1/events?page=1` provides at most 24 published owned events, ordered by canonical start time and stable database ID. It includes past and future publications; time passing does not imply cancellation or withdrawal. Pages are bounded to 1–1000. Numeric values clamp to that range; malformed, nested or over-nine-digit values use page 1. `pagination.total` counts published owned events. A 200 with an empty events array is authoritative for that requested page. It is not an unavailable feed or a fabricated DQOR fallback. Mutable offset pages are not an atomic whole-catalog snapshot; consumers deduplicate IDs and refresh pages after publication changes.

GET `/api/public/v1/events/:id` provides one published event. IDs are opaque strings of the form `hosted-event-101`, stable across title, slug, date and organization-display edits. They share the owned-event identity used by the community foundation. Legacy `dqor-2026`, external discovery IDs, drafts, missing IDs and malformed IDs return 404; request parameters and credentials never expand visibility. This does not confer membership, admission, registration availability, ownership or entitlement on the requester.

The only event fields are ID, explicit `ownership: hosted_event`, title, canonical start/end timestamps, their respective local dates, IANA timezone, public organizer name/slug and the first-party published details path. Each timestamp carries its actual timezone offset, including daylight-saving changes within an event. End date is the date of the end timestamp; clients must not invent occupied days or duration from local clock subtraction. Text is display content, not trusted HTML. Resolve details_path against the approved first-party origin, never a supplied Host header or a third-party registration URL.

No schedule sessions, venue, community membership, capacity, attendees, emails, orders, tickets, prices, QR credentials, passes or redemption state is inferred from these facts. A schedule or protected wallet needs its own explicit contract and authorization. External discovery records remain external and are never adopted into Event ownership. No meals/party/admission behavior changes.

Success schema and synthetic detail/catalog fixtures are `docs/contracts/public_owned_events_v1.*.json`. Fixture IDs and dates do not announce or publish an actual event. Schema `$id` names a document, not an additional deployed endpoint. Clients must reject unsupported schema_version and invalid required data before replacing a cached snapshot. Additive optional changes may preserve v1; incompatible meanings or types require a new major route/schema.

## Revalidation, withdrawal and failure

Each response includes schema_version 1 and a SHA256 content_version over the actual serialized public payload. It is an opaque fingerprint, not a monotonically increasing version or permission token. Public edits and publication membership participate; private-only edits do not. Last-Modified is deliberately absent so same-second or update_columns edits cannot mask changed content.

GET and HEAD support ETag with `Cache-Control: public, max-age=0, must-revalidate`. Retain the exact ETag header, including quotes/weak marker, for If-None-Match. A bodyless 304 permits reuse only of that matching cached page/detail. Without a matching snapshot, fetch again unconditionally. Do not treat another page's content_version as catalog authority.

Unpublication or deletion withdraws the detail: return non-cacheable 404 with `event_not_found`, even when the client supplies an old ETag. Remove its cached detail and do not substitute a demo or another tenant's matching slug. Refetch catalog pages because offsets can change. Offline content is explicitly stale and may contain withdrawn publications until revalidated; it never authorizes an action. No cancellation enum or cancellation policy is invented; disappearance means the publication is unavailable.

Database read failure returns 503/no-store with `events_unavailable`; it does not return a false empty catalog or expose database details. The adjacent error JSON Schema defines stable codes; message text is display copy. Preserve a good snapshot as stale on a 503 and revalidate after recovery. No background push or offline write queue is implied.

## Verification and release boundary

Request regressions must verify both gates, published-only privacy, matching slugs across organizations, stable IDs, malformed/legacy/external/draft rejection, bounded pages, authoritative empty publication, daylight-saving offsets, GET/HEAD revalidation, public edits without timestamp touches, private-edit stability, immediate withdrawal and database-error recovery. Owned headless Brave must consume the JSON and verify withdrawal rather than using a mock mobile transport. Existing public programme, organizer, attendee and staff read contracts need compatibility checks.

Before any integration, require the exact checked head's tests and independent security/testing/Rails/quality/performance approval. Main's existing pipeline can deploy a merge; merge and production release remain approval-gated. Runtime rollback disables PUBLIC_EVENTS_ENABLED and retains existing data. No database rollback is needed for this branch. The native owned-event clients are integrated with Release entry disabled. Exact-source signed builds, physical-device acceptance, live owned-event integration and distribution remain separate validation gates; protected authentication and entitlement scopes remain closed.

Timestamp output preserves the database microsecond precision: `starts_at` and `ends_at` always include six fractional digits and an explicit UTC offset in the named event timezone. Readers continue to accept whole-second v1 timestamps. Strict `ends_at > starts_at` applies to stored and decoded instants. The subsecond and microsecond detail/catalog examples are actual serializer output for synthetic persisted events and are copied independently into native unit-test fixtures.
