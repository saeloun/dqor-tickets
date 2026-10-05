# Ticket-category registration questions

Stacked on reviewed pilot PR169 at `63fdfbc`. This increment does not change the pilot's one active free category, one registration per user/event, capacity lock, checkout isolation, identity/privacy or payment contracts. A form belongs to one existing owned TicketType, including staged draft inventory; it does not activate additional categories. No production migration, flags, email, roster grants or provider changes were made.

## Gates and user journey

`FREE_EVENT_QUESTIONS_ENABLED=true` is required in addition to the two existing pilot gates. All default off. Existing events without a published question version retain their current registration flow. If a published form exists and the questions flag is disabled, new registration fails closed; it never silently skips required questions. Existing tickets remain retrievable. Draft questions never appear to attendees.

Owners/admins use the event's Registration questions section to add, edit, remove and reorder up to 12 questions per category, preview a visibly private draft, and explicitly publish. A frozen published version is displayed read-only. Changed drafts affect future registrations only after a new publish. Optimistic draft revision checks reject stale organizer writes; all operations recheck fresh owner/admin membership and lock the event.

Attendees see only their chosen category's published questions, with visible labels, Required/Optional indicators, inline helper/errors, free admission and identity summary, and one Complete registration action. The dialog's Back/Escape/browser Back returns to the event summary; Continue restores values in document memory. No localStorage, sessionStorage or private service-worker caching is used. Actual page exit clears inputs; reloading or leaving the document does not preserve unsent answers. Server validation failure preserves values and presents the latest schema after a stale-version rejection.

## Types and history

Supported types: short text (200 characters), long text (1000), whole number (-1000000 to 1000000), one choice (2–10 named options), and yes/no. Required no/false is valid; optional blanks are stored as null. Unknown question IDs, non-scalar answers, unsupported controls, stale/wrong category versions and invalid typed values are rejected before any ticket/order is created. No sensitive fields, uploads, email/address/phone questions or consent boxes are provided by default.

Each question has a server-generated UUID retained through edits and reordering. Published versions retain their complete labels/types/choices/requirements and ordering. Responses contain normalized answer values and reference the immutable published version, so label/type/choice changes cannot reinterpret historical answers. Rails models reject update/update_columns/destroy after persistence; there are no edit/delete endpoints or Avo resources for versions/responses. This is application immutability, not a claim that privileged database maintenance cannot change rows.

Registration validation, capacity checking and response insertion share the existing event-locked database transaction. Duplicate retries return the original registration and do not overwrite answers. Composite foreign keys bind forms, versions, responses and tickets to the same event and category. The existing unique event/user registration key is unchanged.

## Privacy and export

Answer request parameters and stored answer fields are redacted through the logging filter. Answers never enter shared User profiles, DQOR networking, legacy commerce, invoices or normal attendee CSV. The separately labelled Download registration answers CSV action rechecks owner/admin access to the exact organization/event/category. It exports ticket ID, version number, question ID, historical label and answer; no bearer credentials, email, billing data or other-category answers. Formula-like labels and values are escaped. Header remains `no-store` through the pilot base controller.

## Schema and validation

Migration `20261003030000` creates free_event_forms, free_event_form_versions and free_event_responses with ownership constraints and adds only a supporting composite ticket index. No backfill. Rollback/reapply and schema loading are exercised solely on disposable `dqor_questions_test`; rollback destroys configured forms/answers and is not suitable after real collection without an approved preservation plan.

Focused requests cover drafts/flags, roles/revocation, foreign organizations/sibling events/categories, stale versions, strict types, log redaction, immutable history, safe export and database ownership. Independent-connection tests cover duplicate submissions and final-capacity races with one response. The real mobile journey covers organizer add/order/preview/publish, choice-control toggling, Back/Continue and browser Back retention, required-error retry, 390px/320px width and final completion without payment/email effects.

Screenshots: `tmp/questions-organizer.png`, `tmp/questions-attendee-mobile.png`, `tmp/questions-attendee-error-mobile.png`, `tmp/questions-attendee-action-mobile.png`, and `tmp/questions-attendee-action-320.png`. Attendee warm/plum tokens follow the design owner's reference; organizer editing retains forest operational tokens. No fictional artwork is presented as a real event image.

Not included: additional active ticket categories, sales windows, conditional/repeating questions, file uploads, transfers, cancellation, waitlists, payment/auth changes, automatic sensitive-field collection, cross-event analytics or new public directories. Published schema history and response snapshots are the extension contract for later reviewed increments.

## Verification checkpoint

Local full suite after revision fix: 730 examples, 0 failures (seeds 45558 and 28542). RuboCop: 407 files, no offenses. Brakeman: 0 warnings. Disposable-database rollback/reapply and schema load passed. Browser evidence for the 390px error/submit and 320px submit views is committed under `docs/free-event-questions/`; the design owner reviewed both 390px captures without a layout blocker.

Independent review found and fixed a first-save revision collision: zero now identifies only an untouched category; first persistence advances to one, rejecting stale save/publish/reorder without modifying the draft. Independent connections verify one first-save winner. Initial hosted CI failed an existing Avo selection test; local targeted and full seed 28542 passed. The test now waits for actual selector-controller readiness and asserts checkbox, retained selection and enabled action before its unchanged navigation/no-attendance checks. This improves diagnostic coverage; it does not establish the original failure cause.
