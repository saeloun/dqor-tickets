# External event discovery

This default-off catalog stores external public facts separately from locally owned events, organizations, memberships, attendees and commerce. It makes no claim to organize these listings or accept their registrations. `EVENT_DISCOVERY_ENABLED=true` exposes `/discover` and `/api/public/v1/discovery/events`; `DISCOVERY_PRODUCT_NAME` changes only the directory label. Merge does not import or enable production data.

## Reviewed source snapshots

`db/discovery_snapshots` contains 2,121 factual event records in 49 source profiles whose profile URLs cover 23 website hostnames. Profiles distinguish organizer/source identities; they are not 49 unique websites. The RubyEvents source is pinned to `cc3b03a20b73891f9b44d1b178a500e2d4a4fb00` and contains 2,061 events/meetup occurrences from 2,404 raw records. The excluded 343 records are series, group and collection entities. The companion React/JavaScript/India pack contributes 60 events. Both were observed October 11, 2026. These counts describe the supplied sources, not a complete worldwide calendar.

Raw source package SHA256 values:

- Ruby JSON: `969858285e629056e0b51d84572f2ed28b155b40bfba68146ca6354c6c301652`
- Companion ZIP: `453b2a81535ccae7dad7a0dffba928db1cae9e523063498730f43ff602b8c996`

`script/discovery/prepare_snapshots.rb` normalizes the two reviewed JSON inputs without executing upstream code or fetching URLs. It imports no descriptions, artwork, logos, videos, speaker biographies or attendee lists. Country codes derive from published IANA zones where possible; missing zones remain missing. HTTP registration links are withheld from the public action, with their original raw records retained outside the repository. Year/month precision never becomes a fabricated day. Seven companion date contradictions and one inverted historical Ruby date range are held for review. The inverted end date is withheld, not corrected by guesswork. Explicit nonconsecutive days are preserved.

## Controlled import and recovery

Run `bin/rails 'discovery:import[path/to/reviewed.json,source-key]'` against the intended database only after source review and activation approval. Validation rejects oversized, nested, unknown-field, private-address, credential-bearing and invalid-date inputs. No public import endpoint, scheduler or automatic production seed exists. Each source refresh runs in a transaction with a PostgreSQL advisory lock. An invalid or older refresh cannot replace its last good data. Missing source records remain visible with a stale notice; absence never implies cancellation. A valid later refresh clears the source failure marker.

An external event canonical URL plus its explicit occurrence date identifies date-only records. Exact timestamps distinguish timed occurrences on the same page/day. A shared group/collection URL requires a source-specific occurrence fingerprint, preserving recurring nights. Cross-source matching merges only identical event URLs with identical date/time anchors; partial or unknown-date identities stay conservative. Similar names and collection URLs across different sources do not imply an automatic match. Source provenance remains attached to every matched record. The first imported source supplies displayed facts; conflicting alternate facts require a reviewed mapping, not automatic overwrite. Source IDs changing canonical URLs require review.

Application rollback disables the gate and runs the prior image while retaining all three additive tables and snapshots. Do not roll the migration down in production with populated data. Migration down/up rehearsal belongs to an empty disposable database. Database backup/restore readiness is a separate prerequisite for production activation.

## Public read contract

HTML and JSON share literal search, topic (`ruby`, `react`, `javascript`, `developer`), region (`global`, `india`, `pune`) and date-period filters. `weekend` means the current/next Saturday–Sunday in Asia/Kolkata, explicitly labelled India in the UI; separated published event days must actually intersect that weekend. Upcoming excludes canceled/review-held listings and uncertain partial dates. A future date with unknown status is labelled status unconfirmed. No unknown timezone or registration availability is invented. The catalog retains past and uncertain records separately.

The versioned API returns factual listing fields, prefixed `discovery-` IDs, source fetch/revision/staleness, paging and counts. It declares `ownership=external_discovery` and `local_rsvp_enabled=false`. It includes no user, tenant, attendee or native ticket data. This is a mobile integration foundation, not a shipped iOS/Android feature; the existing legacy NativeAttendee snapshot/scopes are unchanged.

The compact evergreen list is the default. A local cards variant supports fixture comparison; no real-user conversion experiment is claimed. Inline source actions open the source-listed HTTPS page and do not promise a reserved place. Dates, cancellations, stale sources and uncertain status remain visible. Native registration, groups, following, invitations, billing and notifications are separate milestones.
