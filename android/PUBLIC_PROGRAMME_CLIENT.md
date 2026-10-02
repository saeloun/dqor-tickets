# Disconnected public programme client

Stacked on Android PR #172; only Android files change. Implements the proposed
read-only contract from backend PR #171, `docs/PUBLIC_PROGRAMME_API.md` and
`docs/contracts/public_programme_v1.schema.json`. The bundled
`public_programme_example.json` is that contract's synthetic fixture, copied unchanged.
No live endpoint is connected. The manifest still has no INTERNET permission,
native auth/transport gates remain unchanged, and no credential or attendance
operations are added.

## Review journey

Open Deccan Queen on Rails → Schedule → scroll to **Public feed preview**.
The existing sample schedule/bookmarks and wallet remain separate. The preview
contains explicit synthetic response controls: Published, Unchanged (304),
Withdraw all, Offline and Service unavailable. These invoke the same typed client
used by the unit tests; they never delegate to HTTP. Refresh retries the selected
synthetic response. No unapproved hostname, cookies or authorization is involved.

## Cache and parsing behavior

- `ProgrammeTransport` is an injected suspending interface. Its request exposes
  only the fixed proposed path and optional If-None-Match validator, with no origin.
- Valid 200 snapshots atomically replace both arrays, including empty arrays;
  withdrawn rows do not survive through merging. IDs remain strings; no track is
  inferred or added to the feed DTOs. Text is rendered literally by native Text.
- Exact quoted/weak ETags are retained. Every refresh revalidates. A matching 304
  reuses only its cached snapshot. An orphan or mismatched 304 triggers one
  unconditional retry; a second 304 is an error, never an invented empty success.
- Unsupported schemas, wrong field types, missing required nullable fields,
  malformed dates/offsets, duplicate IDs and inconsistent local dates are rejected
  before replacing cache/validator. Unknown additive v1 fields are tolerated.
- Explicit `Asia/Kolkata` determines time display independently of device timezone.
  Null date/time/speaker/room stay unannounced; no duration/day is invented.
- Typed 503 `programme_unavailable`, transport IO failures and invalid responses
  preserve the last valid snapshot. Stale UI warns about changed/withdrawn sessions.
  Initial errors show no fabricated programme. Loading retains the snapshot; refresh
  is serialized, cancellation restores prior state, and retry preserves search.
- Cache is memory-only for the preview screen lifetime. There is no disk persistence,
  background refresh, retry loop, device connectivity observer or offline mutation.
  The user explicitly refreshes after reconnect. Demo status never asserts live freshness.

## Integration gates

A future approved HTTPS transport needs deployed-target verification, bounded
response/time limits, no credentials/cookies, and integration tests. This increment
provides neither live networking nor an authenticated attendee schedule. Do not
infer attendee access, seat reservations or wallet eligibility from the public feed.
