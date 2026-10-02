# Independent event purposes (draft integration)

This slice is stacked on PR146 (`feature/staff-checkin-flow`). Migration
`20261002170000` is reserved; apply after the check-in migrations. No production
records, entitlements, roles or accounts are provisioned. This is not Ruby Passport.

Staff opens `/event_slots` and chooses regular admission (existing `/checkin`) or
one explicitly named purpose. Organizers with the existing `admin` role can create
and edit schedules; existing `desk` users can scan but cannot configure or correct.
Set up Day1 food, Day1 after-party and Day2 food as separate **drafts** through this
screen. Actual dates, time windows, ticket types, capacity and limits must be
verified with organizers before activating. There are deliberately no live seeds
or defaults assigning meals/party access to all attendees. Times in the form are
Asia/Kolkata; limits default to one redemption per ticket per slot.

POST `/event_slots/:id/redeem` accepts `secret` (the existing QR value) and a
16–100 character alphanumeric/hyphen `request_key`. Use one UUID per deliberate
scan, retaining it across unknown-result retries. The response contains `state`,
`message`, `redeemed_at`, `redemption_id` on success; 422 rejects invalid eligibility,
window, capacity, duplicate entitlement or request-key reuse. Existing staff
session and CSRF rules apply. Never log/persist QR input on the client. The same
camera library as admission is used in an isolated Stimulus adapter. Pending
uncertain requests block new scans until retried. Repeated frames are suppressed;
explicit “Allow a new scan” supports configured multiple redemptions.

Admission state is never changed. Slot, order and ticket row locks serialize
capacity and per-ticket limits. QR request replay returns the original redemption
without consuming another use; the database uniquely constrains slot/request key.
Successful records include actor and timestamp. Admin-only correction retains the
original row, correcting actor, timestamp and reason; it releases capacity and the
ticket's use. Replaying a corrected request cannot create another redemption.

`/account/redemptions` is linked from the account dashboard. It requires a verified
email-link session, scopes to tickets assigned to exactly that account email, and
shows admission timestamps plus redemption/correction history. Team purchasers do
not see another assigned attendee's status here. Existing sessions (including
Google-only sessions) must use an email link once; no unverifiable email claim is
accepted as a new authorization path. No ticket ID parameter, QR secret or claim
token is emitted. Cache-Control is no-store. Status is a server snapshot with
refresh, offline, visibility-change and 30-second stale messaging; it makes no
optimistic success claims and does not queue offline mutations.

Integration: add `/event_slots` navigation to the staff check-in page after agreement
with the PR146 owner. Native clients can use this contract after approved staff
session integration; no native grants or authentication changes are included.

Validation: focused service/request tests, separate-connection race tests for both
capacity and repeated-ticket competition, mobile 375px browser check for purpose,
verified own status and stale messaging. Full suite and static checks recorded in
the PR. All test attendees are synthetic.
