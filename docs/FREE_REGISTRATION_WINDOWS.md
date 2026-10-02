# Free registration windows

Stacked on reviewed PR177 at `1a3b266`. This bounded increment adds registration opening/closing windows to existing free ticket categories. It does not add categories, paid issuance, authentication, sends, production grants or activation.

## Draft and publication

Owners/admins use each category’s Registration window page to save a private draft, inspect its saved preview, then explicitly publish. Saved and public values are separate. Fresh membership and event/category ownership are checked for every read/write under the existing event lock. Optimistic revision checks reject unseen draft publication, including the first-save revision-zero case fixed in PR177. Publishing a window cannot publish an event or category or change capacity. Draft events/categories may be configured privately; their public routes remain unavailable.

Inputs are local wall times in the event’s IANA timezone. Strict minute-level parsing converts them to UTC instants. Nonexistent and ambiguous DST times are rejected with explanatory errors, not silently shifted. Blank opening means immediately; blank closing means event end. Opening must precede effective closing, and closing cannot exceed event end. The saved/published timezone is retained alongside instants; a changed event timezone requires saving/reviewing the draft again before publication. Later event-end changes still bound the effective closing time. Preview and public UI show the named timezone and numerical offset.

## Authoritative states

- Upcoming: before the opening instant; no registration action.
- Available: at or after opening and strictly before closing, with capacity and required-form infrastructure available.
- Sold out: within the time window but no remaining capacity; no registration action.
- Closed: at/after closing or event end, or configured infrastructure is disabled. Temporary unavailability is explained distinctly in text.

Opening is inclusive and closing exclusive. Closed takes precedence over sold out; upcoming takes precedence over capacity. Pages are snapshots of current state, not live countdowns. Every POST checks again after acquiring the existing event lock, before validating answers or creating an order/ticket/response. A form opened before closing cannot issue a ticket after closing. Required questions remain required; unavailable published question infrastructure fails closed.

Existing successful registration retries return the original order before capacity/window rejection, never duplicate tickets or answers. Existing ticket retrieval remains available after closing while the event remains published. Unpublished or otherwise non-published events remain denied by the existing published scope; no archive feature or new archive semantics are introduced.

## Gates, ownership and migration

`FREE_REGISTRATION_WINDOWS_ENABLED=true` is required for configuration and use of published custom windows, alongside the existing platform/pilot flags. All default off. An existing published window with this flag off fails closed for new registration; ticket retrieval remains available with the base pilot enabled. Events with no published custom window retain immediate-opening/event-end behavior. Draft values never reach public state or pages. Dynamic public state pages and private configuration use `Cache-Control: no-store`; no service-worker policy changes.

Migration `20261003040000` was checked unused across all fetched origin refs. It adds only `free_registration_windows`, with event/type foreign keys, composite ownership binding, a unique category row, and ordered-time checks. No backfill. Rollback/reapply/schema loading are tested only on disposable `dqor_windows_test`. Rollback removes configuration and is not a production recovery procedure without a reviewed preservation plan.

## Verification

Request tests cover private drafts and flags, initial stale revisions, exact opening/closing boundaries, successful retries and ticket retrieval, DST gaps/folds and malformed dates, capacity states, cross-tenant/category denial, revoked/non-manager access, composite FK rejection and required-form closing behavior. Independent database connections prove last-place capacity serialization and rejection of a registration waiting on the event lock while an organizer publishes a closed window.

The browser journey uses local datetime controls, preserves invalid values, previews/publishes, and captures Upcoming/Available/Sold out/Closed at 390px and 320px. The design owner reviewed the initial full-page captures and requested state-first hierarchy, attendee plum styling/minimal navigation, same-day date ranges and full-width mobile registration action; those refinements are included. Screenshot-only review does not imply independent functional testing. Evidence is under `docs/free-registration-windows/`.

No production migration, activation, paid services, credential changes or email delivery occurred. Independent review and deployment approval remain separate gates.

Local final verification: 740 examples, 0 failures (seed 14684); RuboCop 417 files clean; Brakeman 0 warnings. Migration down/up and schema load passed on the disposable database.

Independent review corrections: hide pilot-only navigation when the pilot is disabled (signed-in and signed-out coverage, no legacy fallback); preserve required-question and event/category publication blockers in the saved-draft preview; label publication as “Publish saved draft”; display closing-order errors as separate blocks with refreshed 390px/320px error evidence.

Final block-error browser recheck: 1 example, 0 failures (seed 50683), 390px/320px images manually inspected without helper/error overlap.
