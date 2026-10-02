# DQOR public programme API v1

Status: proposed implementation, not deployed. Native owners must use fixtures until
this contract is merged and an approved deployed target is verified. This is a
read-only DQOR-specific feed, independent of organizer tenant pilot/authentication,
commerce, attendee identities, admission and redemption APIs.

## Request and snapshot

GET `/api/public/v1/dqor/programme`, HTTPS, JSON response; no credentials required.
There are no filters, pagination, tenant selectors or write operations. Request
parameters do not expand publication visibility. Consumers should omit cookies and
authorization headers. The endpoint does not create an authenticated session.

200 has `schema_version` (integer 1), `content_version` (opaque SHA256 string),
`event`, `sessions` and `speakers`. `docs/contracts/public_programme_v1.schema.json`
is the success JSON Schema; the adjacent error schema defines the 503 shape.
The `.example.json` file contains synthetic client fixtures only, not real session
IDs or a promised live schedule. Schema `$id` identifies the document; it is not
a separately deployed endpoint. Treat IDs as opaque strings; session/speaker database IDs stay
stable across approved edits. Event ID `dqor-2026` is the existing singleton DQOR,
not a tenant identifier. Event dates/venue/timezone use existing Conference constants.

Sessions come only from canonical `Talk.published`, in the existing public schedule
order. Nullable `starts_at`/`ends_at` are ISO8601 with explicit India-local UTC offset;
`local_date` is the start's date in event timezone, or null when unscheduled. Do not
invent end times/durations or assign an unscheduled session to an arbitrary day.
Strings are display text, not trusted HTML. Room is existing public talk information.
Track and speaker_bio are excluded because current public pages do not expose them.

Speakers satisfy BOTH published and announced. Only public name/title/bio and a
public profile URL are serialized. A published talk linked to a non-public speaker
has null speaker_id and speaker_name; it does not expose private pipeline identity.
Unlinked legacy speaker_name is existing public talk text. No pipeline statuses,
positions, notes, photo/blob signatures, emails, users, tickets, QR secrets or tokens
are returned. `sessions: []` / `speakers: []` is a valid empty publication, not an error.

A 200 is a complete authoritative replacement, not a delta. Remove locally cached
rows absent from it; this is how withdrawals/deletions are conveyed. Approved DB
programme edits (including PR161) are reflected without seed replay, hard-coded
schedule copies, or a new app build. Publication membership and actual serialized
fields participate in content_version; private-only edits do not.

## Conditional caching and errors

Responses use `Cache-Control: public, max-age=0, must-revalidate` and ETag. Save the
exact ETag header (including quotes/weak marker) and send If-None-Match next time.
304 has no body: reuse only the matching stored snapshot and mark it revalidated.
If no matching snapshot exists, fetch again without the condition. ETag/content
version changes on public edit, unpublish or deletion, including update_columns
changes that do not update updated_at. There is deliberately no Last-Modified
validator: timestamp-only checks miss such publication changes and same-second edits.

A database read failure returns 503 and `Cache-Control: no-store` with:
`{"schema_version":1,"error":{"code":"programme_unavailable","message":"Programme temporarily unavailable. Try again later."}}`.
The code is stable; message is display copy. Never replace a good snapshot with an
error, assume empty lists on failure, or mark offline data fresh. Cached offline
content must be clearly stale and revalidated on reconnect; it may contain withdrawn
sessions until refreshed. No server background push or offline mutation is implied.

Clients must reject unsupported schema_version before replacing cached data. Additive
optional fields may arrive within v1; incompatible field/type/meaning changes need a
new major route/schema version. content_version is a content fingerprint, not a
monotonic counter, publication timestamp, or permission token.
